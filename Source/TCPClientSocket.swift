// TCPClientSocket.swift
//
// The MIT License (MIT)
//
// Copyright (c) 2015 Zewo
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#if os(Linux)
    import Glibc
#else
    import Darwin.C
#endif
import CLibvenice
import Foundation

public final class TCPClientSocket {
    private var socket: tcpsock
    public private(set) var closed = false

    init(socket: tcpsock) {
        self.socket = socket
    }

    public init(ip: IP, deadline: Deadline = NoDeadline) throws {
        self.socket = tcpconnect(ip.address, deadline)

        if errno != 0 {
            closed = true
            throw TCPError.lastError
        }
    }

    public init(fileDescriptor: Int32) throws {
        self.socket = tcpattach(fileDescriptor, 0)

        if errno != 0 {
            closed = true
            throw TCPError.lastError
        }
    }

    deinit {
        close()
    }

    public func desc() -> String {
        let peer = tcpaddr(socket)
        var buffer:[Int8] = Array<Int8>(count: 50, repeatedValue: 0)
        let result = ipaddrstr(peer,&buffer)
        let str = String(CString:result,  encoding:NSUTF8StringEncoding)

        return str!
    }

    public func send(data: [Int8], deadline: Deadline = NoDeadline) throws {
        if closed {
            throw TCPError.closedSocketError
        }

        var data = data
        let bytesProcessed = tcpsend(socket, &data, data.count, deadline)

        if errno != 0 {
            throw TCPError.lastErrorWithData(data, bytesProcessed: bytesProcessed, receive: false)
        }
    }

    public func flush(deadline: Deadline = NoDeadline) throws {
        if closed {
            throw TCPError.closedSocketError
        }

        tcpflush(socket, deadline)

        if errno != 0 {
            throw TCPError.lastError
        }
    }

    public func receive(bufferSize bufferSize: Int = 256, deadline: Deadline = NoDeadline) throws -> [Int8] {
        if closed {
            throw TCPError.closedSocketError
        }

        var data: [Int8] = [Int8](count: bufferSize, repeatedValue: 0)
        let bytesProcessed = tcprecv(socket, &data, data.count, deadline)

        if errno != 0 {
            throw TCPError.lastErrorWithData(data, bytesProcessed: bytesProcessed, receive: true)
        }

        return processedDataFromSource(data, bytesProcessed: bytesProcessed)
    }

    public func receiveLowWaterMark(lowWaterMark: Int = 256, highWaterMark: Int = 256, deadline: Deadline = NoDeadline) throws -> [Int8] {
        if closed {
            throw TCPError.closedSocketError
        }

        var data: [Int8] = [Int8](count: highWaterMark, repeatedValue: 0)
        let bytesProcessed = tcprecvlh(socket, &data, lowWaterMark, highWaterMark, deadline)

        if errno != 0 {
            throw TCPError.lastErrorWithData(data, bytesProcessed: bytesProcessed, receive: true)
        }

        return processedDataFromSource(data, bytesProcessed: bytesProcessed)
    }

    public func receive(bufferSize bufferSize: Int = 256, untilDelimiter delimiter: String, deadline: Deadline = NoDeadline) throws -> [Int8] {
        if closed {
            throw TCPError.closedSocketError
        }

        var data: [Int8] = [Int8](count: bufferSize, repeatedValue: 0)
        let bytesProcessed = tcprecvuntil(socket, &data, data.count, delimiter, delimiter.utf8.count, deadline)

        if errno != 0 {
            throw TCPError.lastErrorWithData(data, bytesProcessed: bytesProcessed, receive: true)
        }

        return processedDataFromSource(data, bytesProcessed: bytesProcessed)
    }

    public func attach(fileDescriptor: Int32) throws {
        if !closed {
            tcpclose(socket)
        }

        socket = tcpattach(fileDescriptor, 0)

        if errno != 0 {
            throw TCPError.lastError
        }

        closed = false
    }

    public func detach() throws -> Int32 {
        if closed {
            throw TCPError.closedSocketError
        }

        closed = true
        return tcpdetach(socket)
    }

    public func close() {
        if !closed {
            closed = true
            tcpclose(socket)
        }
    }
}

func remainingDataFromSource(data: [Int8], bytesProcessed: Int) -> [Int8] {
    return Array(data[data.count - bytesProcessed ..< data.count])
}

func processedDataFromSource(data: [Int8], bytesProcessed: Int) -> [Int8] {
    return Array(data[0 ..< bytesProcessed])
}

extension TCPClientSocket {
    public func sendString(string: String, deadline: Deadline = NoDeadline) throws {
        let data = string.utf8.map { Int8($0) }
        try send(data, deadline: deadline)
    }

    public func receiveString(bufferSize bufferSize: Int = 256, untilDelimiter delimiter: String, deadline: Deadline = NoDeadline) throws -> String? {
        var response = try receive(bufferSize: bufferSize, untilDelimiter: delimiter, deadline: deadline)
        response.append(0)
        return String.fromCString(response)
    }

    public func receiveString(bufferSize bufferSize: Int = 256, deadline: Deadline = NoDeadline) throws -> String? {
        var response = try receive(bufferSize: bufferSize, deadline: deadline)
        response.append(0)
        return String.fromCString(response)
    }
}
