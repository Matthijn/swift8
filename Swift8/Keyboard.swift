//
//  Keyboard.swift
//  Swift8
//
//  Created by Matthijn Dijkstra on 18/08/15.
//  Copyright © 2015 Matthijn Dijkstra. All rights reserved.
//

import Cocoa

class Keyboard
{
    
    // Mapping ASCII keycodes to the Chip8 key codes
    let mapping : [UInt8: Int8] = [
        18: 0x1, // 1
        19: 0x2, // 2
        20: 0x3, // 3
        21: 0xC, // 4
        12: 0x4, // q
        13: 0x5, // w
        14: 0x6, // e
        15: 0xD, // r
        0:  0x7, // a
        1:  0x8, // s
        2:  0x9, // d
        3:  0xE, // f
        6:  0xA, // z
        7:  0x0, // x
        8:  0xB, // c
        9:  0xF, // v
    ]
    
    var currentKey : Int8 = -1

    func keyUp(_ event: NSEvent)
    {
        // Key stopped being pressed so setting current key to -1 to represent nothing
        self.currentKey = -1
    }
    
    func keyDown(_ event: NSEvent)
    {
        // Setting the current key as the mapped key
        if let mappedKey = self.mapping[UInt8(event.keyCode)]
        {
            self.currentKey = mappedKey
        }
    }
    
}
