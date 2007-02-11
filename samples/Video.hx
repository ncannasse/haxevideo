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
package samples;

class Video {

	static var host = "rtmp://localhost";
	static var video = "videos/test.flv";

	public static function main() {
		flash.net.NetConnection.defaultObjectEncoding = flash.net.ObjectEncoding.AMF0;
		var p = new VideoPlayer(host,video);
	}

}
