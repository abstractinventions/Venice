// FallibleChannel.swift
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

import Libmill

public struct FallibleChannelGenerator<T> : GeneratorType {
    let channel: FallibleSendingChannel<T>

    public mutating func next() -> Result<T>? {
        return channel.sendResult()
    }
}

public enum Result<T> {
    case Value(T)
    case Error(ErrorType)
    
    public func success(@noescape closure: T -> Void) {
        switch self {
        case .Value(let value): closure(value)
        default: break
        }
    }
    
    public func failure(@noescape closure: ErrorType -> Void) {
        switch self {
        case .Error(let error): closure(error)
        default: break
        }
    }
}

public final class FallibleChannel<T> : SequenceType, FallibleSendable, FallibleReceivable {
    let channel: chan
    public let bufferSize: Int
    private var valuesInBuffer: Int = 0
    public var closed: Bool = false
    private var lastResult: Result<T>?

    private var boxes: [Box<Result<T>>] = []

    public convenience init() {
        self.init(bufferSize: 0)
    }

    public init(bufferSize: Int) {
        self.channel = mill_chmake(strideof(Box<Result<T>>), bufferSize)
        self.bufferSize = bufferSize
    }

    deinit {
        mill_chclose(channel)
    }

    /// Reference that can only send values.
    public lazy var sendingChannel: FallibleSendingChannel<T> = FallibleSendingChannel(self)

    /// Reference that can only receive values.
    public lazy var receivingChannel: FallibleReceivingChannel<T> = FallibleReceivingChannel(self)

    /// Creates a generator.
    public func generate() -> FallibleChannelGenerator<T> {
        return FallibleChannelGenerator(channel: sendingChannel)
    }

    /// Closes the channel. When a channel is closed it cannot receive values anymore.
    public func close() {
        if closed {
            mill_panic("tried to close an already closed channel")
        }

        closed = true

        if var value = lastResult {
            mill_chdone(channel, &value, strideof(Box<Result<T>>))
        } else {
            mill_chdone(channel, nil, strideof(Box<Result<T>>))
        }
    }

    /// Receives a result.
    public func receiveResult(result: Result<T>) {
        if closed {
            mill_panic("send on closed channel")
        }
        lastResult = result
        var box = Box(result)
        boxes.append(box)
        mill_chs(channel, &box, strideof(Box<Result<T>>))

        if bufferSize <= 0 || valuesInBuffer < bufferSize {
            valuesInBuffer++
        }
    }

    /// Receives a value.
    public func receive(value: T) {
        if closed {
            mill_panic("send on closed channel")
        }
        let result = Result<T>.Value(value)
        lastResult = result
        var box = Box(result)
        boxes.append(box)
        mill_chs(channel, &box, strideof(Box<Result<T>>))
        
        if bufferSize <= 0 || valuesInBuffer < bufferSize {
            valuesInBuffer++
        }
    }

    /// Receives an error.
    public func receiveError(error: ErrorType) {
        if closed {
            mill_panic("send on closed channel")
        }
        let wrappedError = Result<T>.Error(error)
        lastResult = wrappedError
        var box = Box(wrappedError)
        boxes.append(box)
        mill_chs(channel, &box, strideof(Box<Result<T>>))

        if bufferSize <= 0 || valuesInBuffer < bufferSize {
            valuesInBuffer++
        }
    }

    /// Sends a value.
    public func send() throws -> T? {
        if closed && valuesInBuffer <= 0 {
            return nil
        }
        let pointer = mill_chr(channel, strideof(Box<Result<T>>))
        if let value = valueFromPointer(pointer) {
            switch value {
            case .Value(let v): return v
            case .Error(let e): throw e
            }
        } else {
            return nil
        }
    }

    /// Sends a result.
    public func sendResult() -> Result<T>? {
        if closed && valuesInBuffer <= 0 {
            return nil
        }
        let pointer = mill_chr(channel, strideof(Box<Result<T>>))
        return valueFromPointer(pointer)
    }
    
    func valueFromPointer(pointer: UnsafeMutablePointer<Void>) -> Result<T>? {
        if closed && valuesInBuffer <= 0 {
            return nil
        } else {
            valuesInBuffer--
            let box = UnsafeMutablePointer<Box<Result<T>>>(pointer).memory
            removeFromBoxes(box)
            let value = box.value
            lastResult = value
            return value
        }
    }

    private func removeFromBoxes(box: Box<Result<T>>) {
        if let index = boxes.indexOf({ $0 === box }) {
            boxes.removeAtIndex(index)
        }
    }
}

extension FallibleChannel {

    public class func fanIn<T>(channels: FallibleChannel<T>...) -> FallibleSendingChannel<T> {
        let fanInChannel = FallibleChannel<T>()
        for channel in channels { go { for element in channel { fanInChannel <- element } } }
        return fanInChannel.sendingChannel
    }

}