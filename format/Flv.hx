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
	FLVAudio( data : haxe.io.Bytes, time : Int );
	FLVVideo( data : haxe.io.Bytes, time : Int );
	FLVMeta( data : haxe.io.Bytes, time : Int );
}

class Flv {

	public static function readHeader( ch : haxe.io.Input ) {
		ch.bigEndian = true;
		if( ch.readString(3) != 'FLV' )
			throw "Invalid signature";
		if( ch.readByte() != 0x01 )
			throw "Invalid version";
		var flags = ch.readByte();
		if( flags & 0xF2 != 0 )
			throw "Invalid type flags "+flags;
		var offset = ch.readUInt30();
		if( offset != 0x09 )
			throw "Invalid offset "+offset;
		var prev = ch.readUInt30();
		if( prev != 0 )
			throw "Invalid prev "+prev;
		return {
			hasAudio : (flags & 1) != 1,
			hasVideo : (flags & 4) != 1,
			hasMeta : (flags & 8) != 1,
		};
	}

	public static function writeHeader( ch : haxe.io.Output ) {
		ch.bigEndian = true;
		ch.writeString("FLV");
		ch.writeByte(0x01);
		ch.writeByte(0x05);
		ch.writeUInt30(0x09);
		ch.writeUInt30(0x00);
	}

	public static function readChunk( ch : haxe.io.Input ) {
		var k = try ch.readByte() catch( e : haxe.io.Eof ) return null;
		var size = ch.readUInt24();
		var time = ch.readUInt24();
		var reserved = ch.readUInt30();
		if( reserved != 0 )
			throw "Invalid reserved "+reserved;
		var data = ch.read(size);
		var size2 = ch.readUInt30();
		if( size2 != 0 && size2 != size + 11 )
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

	public static function writeChunk( ch : haxe.io.Output, chunk : FLVChunk ) {
		var k, data, time;
		switch( chunk ) {
		case FLVAudio(d,t): k = 0x08; data = d; time = t;
		case FLVVideo(d,t): k = 0x09; data = d; time = t;
		case FLVMeta(d,t): k = 0x12; data = d; time = t;
		}
		ch.writeByte(k);
		ch.writeUInt24(data.length);
		ch.writeUInt24(time);
		ch.writeUInt30(0);
		ch.write(data);
		ch.writeUInt30(data.length + 11);
	}

	public static function isVideoKeyFrame( data : haxe.io.Bytes ) {
		return (data.get(0) >> 4) == 1;
	}

}