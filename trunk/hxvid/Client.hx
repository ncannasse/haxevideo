/* ************************************************************************ */
/*																			*/
/*  haXe Video 																*/
/*  Copyright (c)2007 Nicolas Cannasse										*/
/*																			*/
/* This library is free software; you can redistribute it and/or			*/
/* modify it under the terms of the GNU Lesser General Public				*/
/* License as published by the Free Software Foundation; either				*/
/* version 2.1 of the License, or (at your option) any later version.		*/
/*																			*/
/* This library is distributed in the hope that it will be useful,			*/
/* but WITHOUT ANY WARRANTY; without even the implied warranty of			*/
/* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU		*/
/* Lesser General Public License or the LICENSE file for more details.		*/
/*																			*/
/* ************************************************************************ */
package hxvid;

import format.Amf;
import format.Flv;
import format.Rtmp;
import hxvid.Commands;

typedef CommandInfos = {
	var id : Int;
	var h : RtmpHeader;
	var p : RtmpPacket;
}

typedef RtmpMessage = {
	header : RtmpHeader,
	packet : RtmpPacket
}

typedef RtmpStream = {
	var id : Int;
	var channel : Int;
	var audio : Bool;
	var video : Bool;
	var play : {
		var file : String;
		var flv : neko.io.Input;
		var startTime : Float;
		var curTime : Int;
		var blocked : Null<Float>;
		var paused : Null<Float>;
		var cache : List<{ data : String, time : Int, audio : Bool }>;
	};
	var record : {
		var file : String;
		var startTime : Float;
		var flv : neko.io.Output;
	};
}

enum ClientState {
	WaitHandshake;
	WaitHandshakeResponse( hs : String );
	Ready;
	WaitBody( h : RtmpHeader, blen : Int );
}

class Client {

	static var file_security = ~/^[A-Za-z0-9_-][A-Za-z0-9_\/-]*(\.flv)?$/;

	public var socket : neko.net.Socket;
	var server : Server;
	var rtmp : Rtmp;
	var state : ClientState;
	var streams : Array<RtmpStream>;
	var dir : String;
	var commands : Commands<CommandInfos>;

	public function new( serv, s ) {
		server = serv;
		socket = s;
		dir = Server.BASE_DIR;
		state = WaitHandshake;
		streams = new Array();
		rtmp = new Rtmp(null,socket.output);
		commands = new Commands();
		initializeCommands();
	}

	function initializeCommands() {
		commands.add1("connect",cmdConnect,T.Object);
		commands.add1("createStream",cmdCreateStream,T.Null);
		commands.add2("play",cmdPlay,T.Null,T.String);
		commands.add2("deleteStream",cmdDeleteStream,T.Null,T.Int);
		commands.add3("publish",cmdPublish,T.Null,T.String,T.Opt(T.String));
		commands.add3("pause",cmdPause,T.Null,T.Opt(T.Bool),T.Int);
		commands.add2("receiveAudio",cmdReceiveAudio,T.Null,T.Bool);
		commands.add2("receiveVideo",cmdReceiveVideo,T.Null,T.Bool);
		commands.add1("closeStream",cmdCloseStream,T.Null);
		commands.add2("seek",cmdSeek,T.Null,T.Int);
	}

	function addData( h : RtmpHeader, data : String, audio : Bool ) {
		var s = streams[h.src_dst];
		if( s == null )
			throw "Unknown stream "+h.src_dst;
		if( s.record == null )
			throw "Publish not done on stream "+h.src_dst;
		var time = Std.int((neko.Sys.time() - s.record.startTime) * 1000);
		var chunk = (if( audio ) FLVAudio else FLVVideo)(data,time);
		Flv.writeChunk(s.record.flv,chunk);
	}

	function error( i : CommandInfos, msg : String ) {
		rtmp.send(i.h.channel,PCall("onStatus",0,[
			ANull,
			Amf.encode({
				level : "error",
				code : "NetStream.Error",
				details : msg,
			})
		]),null,i.h.src_dst);
		throw "ERROR "+msg;
	}

	function securize( i, file : String ) {
		if( !file_security.match(file) )
			error(i,"Invalid file name "+file);
		if( file.indexOf(".") == -1 )
			file += ".flv";
		return dir + file;
	}

	function getStream( i : CommandInfos, ?play : Bool ) {
		var s = streams[i.h.src_dst];
		if( s == null || (play && s.play == null) )
			error(i,"Invalid stream id "+i.h.src_dst);
		return s;
	}

	function openFLV( file ) : neko.io.Input {
		var flv;
		try {
			flv = neko.io.File.read(file,true);
			Flv.readHeader(flv);
		} catch( e : Dynamic ) {
			if( flv != null ) {
				flv.close();
				throw "Corrupted FLV File '"+file+"'";
			}
			throw "FLV file not found '"+file+"'";
		}
		return flv;
	}

	function cmdConnect( i : CommandInfos, obj : Hash<AmfValue> ) {
		var app;
		if( (app = Amf.string(obj.get("app"))) == null )
			error(i,"Invalid 'connect' parameters");
		if( app != "" && !file_security.match(app) )
			error(i,"Invalid application path");
		dir = dir + app;
		if( dir.charAt(dir.length-1) != "/" )
			dir = dir + "/";
		rtmp.send(i.h.channel,PCall("_result",i.id,[
			ANull,
			Amf.encode({
				level : "status",
				code : "NetConnection.Connect.Success",
				description : "Connection succeeded."
			})
		]));
	}

	function cmdCreateStream( i : CommandInfos, _ : Void ) {
		var s = allocStream();
		rtmp.send(i.h.channel,PCall("_result",i.id,[
			ANull,
			ANumber(s.id)
		]));
	}

	function cmdPlay( i : CommandInfos, _ : Void, file : String ) {
		var s = streams[i.h.src_dst];
		if( s == null )
			error(i,"Unknown 'play' channel");
		if( s.play != null )
			error(i,"This channel is already playing a FLV");
		file = securize(i,file);
		s.channel = i.h.channel;
		s.play = {
			file : file,
			flv : null,
			startTime : null,
			curTime : 0,
			blocked : null,
			paused : null,
			cache : null,
		};
		seek(s,0);
		rtmp.send(s.channel,PCall("onStatus",0,[
			ANull,
			Amf.encode({
				level : "status",
				code : "NetStream.Play.Reset",
				description : "Resetting "+file+".",
				details : file,
				clientId : s.id
			})
		]),null,s.id);
		rtmp.send(s.channel,PCall("onStatus",0,[
			ANull,
			Amf.encode({
				level : "status",
				code : "NetStream.Play.Start",
				description : "Start playing "+file+".",
				clientId : s.id
			})
		]),null,s.id);
	}

	function cmdDeleteStream( i : CommandInfos, _ : Void, stream : Int ) {
		var s = streams[stream];
		if( s == null )
			error(i,"Invalid 'deleteStream' streamid");
		closeStream(s);
	}

	function cmdPublish( i : CommandInfos, _ : Void, file : String, shareName : String ) {
		var s = streams[i.h.src_dst];
		if( s == null || s.record != null )
			error(i,"Invalid 'publish' streamid'");
		file = securize(i,file);
		var flv : neko.io.Output = neko.io.File.write(file,true);
		Flv.writeHeader(flv);
		s.record = {
			file : file,
			startTime : neko.Sys.time(),
			flv : flv,
		};
	}

	function cmdPause( i : CommandInfos, _ : Void, ?pause : Bool, time : Int ) {
		var s = getStream(i,true);
		if( pause == null )
			pause = (s.play.paused == null); // toggle
		if( pause ) {
			if( s.play.paused == null )
				s.play.paused = neko.Sys.time();
			rtmp.send(2,PCommand(s.id,CPlay));
		} else {
			if( s.play.paused != null ) {
				s.play.paused = null;
				seek(s,time);
			}
		}
		rtmp.send(i.h.channel,PCall("_result",i.id,[
			ANull,
			Amf.encode({
				level : "status",
				code : if( pause ) "NetStream.Pause.Notify" else "NetStream.Unpause.Notify",
			})
		]));
	}

	function cmdReceiveAudio( i : CommandInfos, _ : Void, flag : Bool ) {
		var s = getStream(i);
		s.audio = flag;
	}

	function cmdReceiveVideo( i : CommandInfos, _ : Void, flag : Bool ) {
		var s = getStream(i);
		s.video = flag;
	}

	function cmdCloseStream( i : CommandInfos, _ : Void ) {
		var s = getStream(i);
		closeStream(s);
	}

	function cmdSeek( i : CommandInfos, _ : Void, time : Int ) {
		var s = getStream(i,true);
		seek(s,time);
		rtmp.send(s.channel,PCall("_result",0,[
			ANull,
			Amf.encode({
				level : "status",
				code : "NetStream.Seek.Notify",
			})
		]),null,s.id);
		rtmp.send(s.channel,PCall("onStatus",0,[
			ANull,
			Amf.encode({
				level : "status",
				code : "NetStream.Play.Start",
			})
		]),null,s.id);
	}

	public function processPacket( h : RtmpHeader, p : RtmpPacket ) {
		switch( p ) {
		case PCall(cmd,iid,args):
			if( !commands.has(cmd) )
				throw "Unknown command "+cmd+"("+args.join(",")+")";
			var infos = {
				id : iid,
				h : h,
				p : p,
			};
			if( !commands.execute(cmd,infos,args) )
				throw "Mismatch arguments for '"+cmd+"' : "+Std.string(args);
		case PAudio(data):
			addData(h,data,true);
		case PVideo(data):
			addData(h,data,false);
		case PCommand(sid,cmd):
			trace("COMMAND "+Std.string(cmd)+":"+sid);
		case PBytesReaded(b):
			//trace("BYTESREADED "+b);
		case PUnknown(k,data):
			trace("UNKNOWN "+k+" ["+data.length+"bytes]");
		}
	}

	function allocStream() {
		var ids = new Array();
		for( s in streams )
			if( s != null )
				ids[s.id] = true;
		var id = 1;
		while( id < ids.length ) {
			if( ids[id] == null )
				break;
			id++;
		}
		var s = {
			id : id,
			channel : null,
			play : null,
			record : null,
			audio : true,
			video : true,
		};
		streams[s.id] = s;
		return s;
	}

	function closeStream( s : RtmpStream ) {
		if( s.play != null && s.play.flv != null )
			s.play.flv.close();
		if( s.record != null )
			s.record.flv.close();
		streams[s.id] = null;
	}

	function seek( s : RtmpStream, seekTime : Int ) {
		// clear
		rtmp.send(2,PCommand(s.id,CPlay));
		rtmp.send(2,PCommand(s.id,CReset));
		rtmp.send(2,PCommand(s.id,CClear));

		// reset infos
		var p = s.play;
		var now = neko.Sys.time();
		p.startTime = now - Server.FLV_BUFFER_TIME - seekTime / 1000;
		if( p.paused != null )
			p.paused = now;
		p.blocked = null;
		if( p.flv != null )
			p.flv.close();
		p.flv = openFLV(p.file);
		p.cache = new List();

		// prepare to send first audio + video chunk (with null timestamp)
        var audio = s.audio;
        var video = s.video;
		var audioCache = null;
		while( true ) {
			var c = Flv.readChunk(s.play.flv);
			if( c == null )
				break;
			switch( c ) {
			case FLVAudio(data,time):
				if( time < seekTime )
					continue;
				audioCache = { data : data, time : time, audio : true };
				if( !audio )
					break;
				audio = false;
			case FLVVideo(data,time):
				var keyframe = Flv.isVideoKeyFrame(data);
				if( keyframe )
					p.cache = new List();
				p.cache.add({ data : data, time : time, audio : false });
				if( time < seekTime )
					continue;
				if( !video )
					break;
				video = false;
			case FLVMeta(data,time):
				// skip
			}
			if( !audio && !video )
				break;
		}
		if( audioCache != null )
			p.cache.push(audioCache);
	}

	public function playFLV( t : Float, s : RtmpStream ) {
		var p = s.play;
		if( p.paused != null )
			return;
		if( p.blocked != null ) {
			var delta = t - p.blocked;
			p.startTime += delta;
			p.blocked = null;
		}
		if( p.cache != null ) {
			while( true ) {
				var f = p.cache.pop();
				if( f == null ) {
					p.cache = null;
					break;
				}
				if( f.audio ) {
					if( s.audio )
						rtmp.send(s.channel,PAudio(f.data),f.time,s.id);
				} else {
					if( s.video )
						rtmp.send(s.channel,PVideo(f.data),f.time,s.id);
				}
				p.curTime = f.time;
				if( server.isBlocking(socket) ) {
					p.blocked = t;
					return;
				}
			}
		}
		var reltime = Std.int((t - p.startTime) * 1000);
		while( reltime > p.curTime ) {
			var c = Flv.readChunk(p.flv);
			if( c == null ) {
				p.flv.close();
				s.play = null;
				// TODO : notice the client
				return;
			}
			switch( c ) {
			case FLVAudio(data,time):
				if( s.audio )
					rtmp.send(s.channel,PAudio(data),time,s.id);
				p.curTime = time;
			case FLVVideo(data,time):
				if( s.video )
					rtmp.send(s.channel,PVideo(data),time,s.id);
				p.curTime = time;
			case FLVMeta(data,time):
				// skip
			}
			if( server.isBlocking(socket) ) {
				p.blocked = t;
				return;
			}
		}
		server.wakeUp( socket, Server.FLV_BUFFER_TIME / 2 );
	}

	public function updateTime( t : Float ) {
		for( s in streams )
			if( s != null && s.play != null )
				playFLV(t,s);
	}

	public function cleanup() {
		for( s in streams )
			if( s != null )
				closeStream(s);
		streams = new Array();
	}

	public function readProgressive( buf, pos, len ) {
		switch( state ) {
		case WaitHandshake:
			if( len < Rtmp.HANDSHAKE_SIZE + 1 )
				return null;
			rtmp.i = new neko.io.StringInput(buf,pos,len);
			rtmp.readWelcome();
			var hs = rtmp.readHandshake();
			rtmp.writeWelcome();
			rtmp.writeHandshake(hs);
			state = WaitHandshakeResponse(hs);
			return { msg : null, bytes : Rtmp.HANDSHAKE_SIZE + 1 };
		case WaitHandshakeResponse(hs):
			if( len < Rtmp.HANDSHAKE_SIZE )
				return null;
			rtmp.i = new neko.io.StringInput(buf,pos,len);
			var hs2 = rtmp.readHandshake();
			if( hs != hs2 )
				throw "Invalid Handshake";
			rtmp.writeHandshake(hs);
			state = Ready;
			return { msg : null, bytes : Rtmp.HANDSHAKE_SIZE };
		case Ready:
			var hsize = rtmp.getHeaderSize(buf.charCodeAt(pos));
			if( len < hsize )
				return null;
			rtmp.i = new neko.io.StringInput(buf,pos,len);
			var h = rtmp.readHeader();
			state = WaitBody(h,rtmp.bodyLength(h,true));
			return { msg : null, bytes : hsize };
		case WaitBody(h,blen):
			if( len < blen )
				return null;
			rtmp.i = new neko.io.StringInput(buf,pos,len);
			var p = rtmp.readPacket(h);
			var msg = if( p != null ) { header : h, packet : p } else null;
			state = Ready;
			return { msg : msg, bytes : blen };
		}
		return null;
	}
}
