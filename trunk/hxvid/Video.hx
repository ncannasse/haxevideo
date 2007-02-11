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

class Video {

	static var nc;

	static function display(e) {
		trace(e.info);
		if( e.info.code == "NetConnection.Connect.Success" ) {
			var mc = flash.Lib.current;
			var st = mc.stage;
			var v = new flash.media.Video(st.stageWidth,st.stageHeight);
			mc.addChild(v);

			var ns = new flash.net.NetStream(nc);
			ns.addEventListener(flash.events.NetStatusEvent.NET_STATUS,display);
			v.attachNetStream(ns);
			ns.play("videos/test.flv");
		}
	}

	public static function main() {
		trace("Connecting...");
		flash.net.NetConnection.defaultObjectEncoding = flash.net.ObjectEncoding.AMF0;

		nc = new flash.net.NetConnection();
		nc.addEventListener(flash.events.NetStatusEvent.NET_STATUS,display);
		//nc.connect(null);
		nc.connect("rtmp://localhost");
	}

}
