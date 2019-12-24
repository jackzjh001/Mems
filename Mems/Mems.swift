//
//  Mems.swift
//  Mems
//
//  Created by MJ Lee on 2019/6/22.
//  Copyright © 2019 MJ Lee. All rights reserved.
//

import Foundation

public enum MemAlign : Int {
    case one = 1, two = 2, four = 4, eight = 8
}

private let _EMPTY_PTR = UnsafeRawPointer(bitPattern: 0x1)!

/// 辅助查看内存的小工具类
public struct Mems<T> {
    
    /// 根据内存地址起始点和长度，根据对齐格式进行分段读取，因为是16进制打印，所以 aligment * 2
    private static func _memStr(_ ptr: UnsafeRawPointer,
                                _ size: Int,
                                _ aligment: Int) ->String {
        if ptr == _EMPTY_PTR { return "" }
        
        var rawPtr = ptr
        var string = ""
        let fmt = "0x%0\(aligment << 1)lx"
        let count = size / aligment
        for i in 0..<count {
            if i > 0 {
                string.append(" ")
                rawPtr += aligment
            }
            let value: CVarArg
            switch aligment {
            case MemAlign.eight.rawValue:
                value = rawPtr.load(as: UInt64.self)
            case MemAlign.four.rawValue:
                value = rawPtr.load(as: UInt32.self)
            case MemAlign.two.rawValue:
                value = rawPtr.load(as: UInt16.self)
            default:
                value = rawPtr.load(as: UInt8.self)
            }
            string.append(String(format: fmt, value))
        }
        return string
    }
    
    private static func _memBytes(_ ptr: UnsafeRawPointer,
                                  _ size: Int) -> [UInt8] {
        var arr: [UInt8] = []
        if ptr == _EMPTY_PTR { return arr }
        for i in 0..<size {
            arr.append((ptr + i).load(as: UInt8.self))
        }
        return arr
    }
    
    /// 获得变量的内存数据（字节数组格式） ex: var str = "0123456789ABCDE" -> [48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 65, 66, 67, 68, 69, 239]
    public static func memBytes(ofVal v: inout T) -> [UInt8] {
        return _memBytes(ptr(ofVal: &v), MemoryLayout.stride(ofValue: v))
    }
    
    /// 获得引用所指向的内存数据（字节数组格式）
    public static func memBytes(ofRef v: T) -> [UInt8] {
        let p = ptr(ofRef: v)
        return _memBytes(p, malloc_size(p))
    }
    
    /// 获得变量的内存数据（字符串格式）：取到变量内存地址，根据变量所占内存空间，读其内容，针对值类型变量：枚举、结构体（String， Array特殊判断）
    ///
    /// - Parameter alignment: 决定了多少个字节为一组
    public static func memStr(ofVal v: inout T, alignment: MemAlign? = nil) -> String {
        let p = ptr(ofVal: &v)
        return _memStr(p, MemoryLayout.stride(ofValue: v),
                       alignment != nil ? alignment!.rawValue : MemoryLayout.alignment(ofValue: v))
    }
    
    /// 获得引用所指向的内存数据（字符串格式）：取到变量内存地址，根据变量所占内存空间，读其内容，针对引用类型变量，引用性变量指向的是堆空间内存，变量实际分配空间为16的倍数
    ///
    /// - Parameter alignment: 决定了多少个字节为一组
    public static func memStr(ofRef v: T, alignment: MemAlign? = nil) -> String {
        let p = ptr(ofRef: v)
        return _memStr(p, malloc_size(p),
                       alignment != nil ? alignment!.rawValue : MemoryLayout.alignment(ofValue: v))
    }
    
    /// 获得变量的内存地址
    public static func ptr(ofVal v: inout T) -> UnsafeRawPointer {
        return MemoryLayout.size(ofValue: v) == 0 ? _EMPTY_PTR : withUnsafePointer(to: &v) {
            UnsafeRawPointer($0)
        }
    }
    
    /// 获得引用所指向内存的地址
    public static func ptr(ofRef v: T) -> UnsafeRawPointer {
        if v is Array<Any>
            || Swift.type(of: v) is AnyClass
            || v is AnyClass {  // 数组 类实例 类的元类型
            return UnsafeRawPointer(bitPattern: unsafeBitCast(v, to: UInt.self))!
        } else if v is String {
            var mstr = v as! String
            if mstr.mems.type() != .heap { // 非堆上的string也就不存在指针引用的问题，变量本身已经存储了字符串内容
                return _EMPTY_PTR
            }
            /// 堆空间第9-16位才是字符串内容的堆空间地址，前八位是字符串的一些描述信息，比如长度，标志位
            return UnsafeRawPointer(bitPattern: unsafeBitCast(v, to: (UInt, UInt).self).1)!
        } else {
            return _EMPTY_PTR
        }
    }
    
    /// 获得变量所占用的内存大小 ：实际分配内存，由于字节对齐( MemoryLayout.alignment)，可能大于所需要内存
    public static func size(ofVal v: inout T) -> Int {
        return MemoryLayout.size(ofValue: v) > 0 ? MemoryLayout.stride(ofValue: v) : 0
    }
    
    /// 获得引用所指向内存的大小： 实际分配内存，由于字节对齐( 堆空间的对齐长度为16)，可能大于所需要内存
    public static func size(ofRef v: T) -> Int {
        return malloc_size(ptr(ofRef: v))
    }
}

public enum StringMemType : UInt8 {
    /// TEXT段（常量区） 大于15位，且字面量初始化 ex: let str = "0123456789ABCDEF"  0xd000 0000 0000 0010 0x8000 0001 0000 a790 标志位为 0xd
    case text = 0xd0
    /// taggerPointer  小于15位 ex: let str = "0123456789ABCDE" // 0x3736353433323130 0xef45444342413938 标志位为 0xe
    case tagPtr = 0xe0
    /// 堆空间           动态初始化，且大于15位 let str = "0123456789ABCDEF" str.append("G") 0xf000000000000010 0x0000000100689760 标志位为 0xf
    case heap = 0xf0
    /// 未知
    case unknow = 0xff
}

public struct MemsWrapper<Base> {
    public private(set) var base: Base
    public init(_ base: Base) {
        self.base = base
    }
}

public protocol MemsCompatible {}
public extension MemsCompatible {
    static var mems: MemsWrapper<Self>.Type {
        get { return MemsWrapper<Self>.self }
        set {}
    }
    var mems: MemsWrapper<Self> {
        get { return MemsWrapper(self) }
        set {}
    }
}

extension String: MemsCompatible {}
public extension MemsWrapper where Base == String {
    mutating func type() -> StringMemType {
        let ptr = Mems.ptr(ofVal: &base)
        /// 取到里面的标志位信息，决定这个字符串的类型
        return StringMemType(rawValue: (ptr + 15).load(as: UInt8.self) & 0xf0)
            ?? StringMemType(rawValue: (ptr + 7).load(as: UInt8.self) & 0xf0)
            ?? .unknow
    }
}
