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
import hxvid.Client;

class Server extends neko.net.ThreadServer<Client,RtmpMessage> {

	public static var FLV_BUFFER_TIME : Float = 5; // 5 seconds of buffering
	public static var CLIENT_BUFFER_SIZE = (1 << 16); // 64 KB output buffer
	public static var BASE_DIR = "videos/";
	static var CID = 0;

	var clients : List<Client>;

	function new() {
		super();
		clients = new List();
		updateTime = 0.1;
	}

	public function clientConnected(s : neko.net.Socket) {
		var c = new Client(s);
		clients.add(c);
		return c;
	}

	public function clientDisconnected( c : Client ) {
		c.stop();
		clients.remove(c);
	}

	public function clientMessage( c : Client, msg : RtmpMessage ) {
		if( msg != null ) {
			try {
				c.processPacket(msg.header,msg.packet);
			} catch( e : Dynamic ) {
				stopClient(c.socket);
				logError(e);
			}
		}
	}

	public function readClientMessage( c : Client, buf : String, pos : Int, len : Int ) {
		return c.readProgressive(buf,pos,len);
	}

	public function afterEvent() {
		var mst = neko.Sys.time();
		for( c in clients )
			try {
				c.updateTime(mst);
			} catch( e : Dynamic ) {
				c.stop();
				stopClient(c.socket);
				logError(e);
			}
	}

	static function main() {
		var s = new Server();
		var args = neko.Sys.args();
		var server = args[0];
		var port = Std.parseInt(args[1]);
		if( server == null )
			server = "localhost";
		if( port == null )
			port = 1935;
		neko.Lib.println("Starting haXe Video Server on "+server+":"+port);
		s.run(server,port);
	}

}
