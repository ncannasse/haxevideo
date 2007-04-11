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
	var rtmp : Rtmp;
	var state : ClientState;
	var output : neko.net.SocketBufferedOutput;
	var streams : Array<RtmpStream>;
	var dir : String;

	public function new( s ) {
		socket = s;
		dir = Server.BASE_DIR;
		output = new neko.net.SocketBufferedOutput(socket,Server.CLIENT_BUFFER_SIZE);
		state = WaitHandshake;
		streams = new Array();
		rtmp = new Rtmp(null,output);
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

	function error( h : RtmpHeader, msg : String ) {
		rtmp.send(h.channel,PCall("onStatus",0,[
			ANull,
			Amf.encode({
				level : "error",
				code : "NetStream.Error",
				details : msg,
			})
		]),null,h.src_dst);
		throw "ERROR "+msg;
	}

	function securize( h, file : String ) {
		if( !file_security.match(file) )
			error(h,"Invalid file name "+file);
		if( file.indexOf(".") == -1 )
			file += ".flv";
		return dir + file;
	}

	function getStream( h : RtmpHeader, ?play : Bool ) {
		var s = streams[h.src_dst];
		if( s == null || (play && s.play == null) )
			error(h,"Invalid stream id "+h.src_dst);
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

	public function processPacket( h : RtmpHeader, p : RtmpPacket ) {
		switch( p ) {
		case PCall(cmd,iid,args):
			switch( cmd ) {
			case "connect":
				trace("CONNECT");
				var obj, app;
				if( args.length != 1 || (obj = Amf.object(args[0])) == null || (app = Amf.string(obj.get("app"))) == null )
					error(h,"Invalid 'connect' parameters");
				if( app != "" && !file_security.match(app) )
					error(h,"Invalid application path");
				dir = dir + app;
				if( dir.charAt(dir.length-1) != "/" )
					dir = dir + "/";
				rtmp.send(h.channel,PCall("_result",iid,[
					ANull,
					Amf.encode({
						level : "status",
						code : "NetConnection.Connect.Success",
						description : "Connection succeeded."
					})
				]));
			case "createStream":
				trace("CREATESTREAM");
				var s = allocStream();
				rtmp.send(h.channel,PCall("_result",iid,[
					ANull,
					ANumber(s.id)
				]));
			case "play":
				var s = streams[h.src_dst];
				if( s == null )
					error(h,"Unknown 'play' channel");
				if( s.play != null )
					error(h,"This channel is already playing a FLV");
				var file, flv;
				if( args.length != 2 || args[0] != ANull || (file = Amf.string(args[1])) == null )
					error(h,"Invalid 'play' arguments");
				file = securize(h,file);
				trace("PLAY '"+file+"'");
				s.channel = h.channel;
				s.play = {
					file : file,
					flv : null,
					startTime : null,
					curTime : 0,
					blocked : null,
					paused : null,
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
			case "deleteStream":
				var stream;
				if( args.length != 2 || args[0] != ANull || (stream = Amf.number(args[1])) == null )
					error(h,"Invalid 'deleteStream' arguments");
				var s = streams[Std.int(stream)];
				if( s == null )
					error(h,"Invalid 'deleteStream' streamid");
				trace("DELETESTREAM "+stream);
				closeStream(s);
			case "publish":
				var s = streams[h.src_dst];
				if( s == null || s.record != null )
					error(h,"Invalid 'publish' streamid'");
				var file;
				if( args.length != 3 || args[0] != ANull || (file = Amf.string(args[1])) == null )
					error(h,"Invalid 'publish' arguments");
				if( Amf.string(args[2]) != "record" )
					error(h,"Need 'record' argument");
				file = securize(h,file);
				trace("PUBLISH '"+file+"'");
				var flv : neko.io.Output = neko.io.File.write(file,true);
				Flv.writeHeader(flv);
				s.record = {
					file : file,
					startTime : neko.Sys.time(),
					flv : flv,
				};
			case "pause":
				var s = getStream(h,true);
				// Undefined arg = togglePause()
				var pause = if( args[1] == AUndefined ) (s.play.paused == null) else Amf.bool(args[1]);
				var time;
				if( args.length != 3 || args[0] != ANull || pause == null || (time = Std.int(Amf.number(args[2]))) == null )
					error(h,"Invalid 'pause' arguments");
				if( pause ) {
					trace("PAUSE "+s.id);
					if( s.play.paused == null )
						s.play.paused = neko.Sys.time();
					rtmp.send(2,PCommand(s.id,CPlay));
				} else {
					trace("RESUME "+s.id);
					if( s.play.paused != null ) {
						s.play.paused = null;
						seek(s,time);
					}
				}
				rtmp.send(h.channel,PCall("_result",iid,[
					ANull,
					Amf.encode({
						level : "status",
						code : if( pause ) "NetStream.Pause.Notify" else "NetStream.Unpause.Notify",
					})
				]));
			case "receiveAudio":
				var s = getStream(h);
				s.audio = Amf.bool(args[1]);
			case "receiveVideo":
				var s = getStream(h);
				s.video = Amf.bool(args[1]);
			case "closeStream":
				var s = getStream(h);
				trace("CLOSE "+s.id);
				if( args.length != 1 || args[0] != ANull )
					error(h,"Invalid 'closeStream' arguments");
				closeStream(s);
			case "seek":
				var s = getStream(h,true);
				var time;
				if( args.length != 2 || args[0] != ANull || (time = Std.int(Amf.number(args[1]))) == null )
					error(h,"Invalid 'seek' arguments");
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
			default:
				throw "Unknown command "+cmd+"("+args.join(",")+")";
			}
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
		// reset (compat with haxe 1.12)
		var o : { private var bytes : Int; } = output;
		o.bytes = 0;

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

		// prepare to send first audio + video chunk (with null timestamp)
        var audio = s.audio;
        var video = s.video;
		var frames = new List();
		while( true ) {
			var c = Flv.readChunk(s.play.flv);
			if( c == null )
				break;
			switch( c ) {
			case FLVAudio(data,time):
				if( time < seekTime )
					continue;
				if( s.audio )
					rtmp.send(s.channel,PAudio(data),if( audio ) null else time,s.id);
				audio = false;
			case FLVVideo(data,time):
				var keyframe = Flv.isVideoKeyFrame(data);
				if( keyframe )
					frames = new List();
				frames.add({ data : data, time : time});
				if( time < seekTime )
					continue;
				if( s.video )
					for( f in frames ) {
						rtmp.send(s.channel,PVideo(f.data),if( video ) null else f.time,s.id);
						video = false;
					}
				video = false;
			case FLVMeta(data,time):
				// skip
			}
			if( !audio && !video )
				break;
		}
	}

	public function playFLV( t : Float, s : RtmpStream ) {
		var p = s.play;
		if( p.paused != null )
			return;
		if( p.blocked != null ) {
			output.flush();
			if( output.writable() ) {
				p.startTime += t - p.blocked;
				p.blocked = null;
			} else
				return;
		}
		var reltime = Std.int((t - p.startTime) * 1000);
		while( reltime > p.curTime ) {
			var c = Flv.readChunk(p.flv);
			if( c == null ) {
				p.flv.close();
				s.play = null;
				// TODO : notice the client
				break;
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
			if( !output.writable() ) {
				trace("BUFFER FULL");
				p.blocked = t;
				break;
			}
		}
	}

	public function updateTime( t : Float ) {
		for( s in streams )
			if( s != null && s.play != null )
				playFLV(t,s);
	}

	public function stop() {
		for( s in streams )
			if( s != null )
				closeStream(s);
		streams = new Array();
	}

}
