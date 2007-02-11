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
package format;

enum FLVChunk {
	FLVAudio( data : String, time : Int );
	FLVVideo( data : String, time : Int );
	FLVMeta( data : String, time : Int );
}

class Flv {

	var ch : neko.io.Input;

	public function new( ch : neko.io.Input ) {
		this.ch = ch;
		readHeader();
	}

	function readHeader() {
		if( ch.read(3) != 'FLV' )
			throw "Invalid signature";
		if( ch.readChar() != 0x01 )
			throw "Invalid version";
		var flags = ch.readChar();
		if( flags != 0x05 && flags != 0x01 )
			throw "Invalid type flags";
		if( ch.readUInt32B() != 0x09 )
			throw "Invalid offset";
		if( ch.readUInt32B() != 0 )
			throw "Invalid prev 0";
	}

	public function readChunk() {
		var k = try ch.readChar() catch( e : neko.io.Eof ) return null;
		var size = ch.readUInt24B();
		var time = ch.readUInt24B();
		var reserved = ch.readUInt32B();
		if( reserved != 0 )
			throw "Invalid reserved "+reserved;
		var data = ch.read(size);
		var size2 = ch.readUInt32B();
		if( size2 != size + 11 )
			throw "Invalid size2 ("+size+" != "+size2+")";
		return switch( k ) {
		case 0x08:
			FLVAudio(data,time);
		case 0x09:
			FLVVideo(data,time);
		case 0x12:
			FLVMeta(data,time);
		default:
			throw "Invalid FLV tag "+k;
		}
	}

	public function close() {
		ch.close();
	}

}