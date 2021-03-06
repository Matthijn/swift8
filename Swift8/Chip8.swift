//
//  Chip8.swift
//  Swift8
//
//  Created by Matthijn Dijkstra on 18/08/15.
//  Copyright © 2015 Matthijn Dijkstra. All rights reserved.
//  Based on technical documentation found on http://devernay.free.fr/hacks/chip8/C8TECH10.HTM#00E0

import Foundation

// Will hold the callback that belongs to the opcode, so the correct code for that opcode can be easily executed
struct Opcode
{
    let code : UInt16
    let callback: ((UInt16) -> Void)
}

class Chip8
{
    // Total memory size
    static let MemorySize = 4096
    
    // Total register size
    static let RegisterSize = 16
    
    // Total stack size
    static let StackSize = 16

    // The location from where the fonts are going to be stored in memory
    static let FontMemoryLocation : UInt16 = 0
    
    // The location from where roms are loaded
    static let RomLocation : UInt16 = 0x200
    
    // Will hold the current rom
    var rom : Data?
    
    // Will hold the memory
    var memory = [UInt8](repeating: 0, count: Chip8.MemorySize)
    
    // The register (last item in the register (VF) doubles as carry flag)
    var V = [UInt8](repeating: 0, count: Chip8.RegisterSize)
    
    // The address register
    var I : UInt16 = 0
    
    // The stack
    var stack = [UInt16](repeating: 0, count: Chip8.StackSize)

    // Points to the current item in the stack
    var sp : UInt8 = 0
    
    // The program counter (e.g holds current executing memory address)
    var pc : UInt16 = 0
    
    // Used for delaying things, counts down from any non zero number at 60hz
    var delayTimer : UInt8 = 0
    
    // Used for sounding a beep when it is non zero, counts down at 60hz
    var soundTimer : UInt8 = 0
    
    // Flag to keep track if we are playing a sound
    var isPlayingSound = false;
    
    // Flag to stop looping if needed
    var isRunning = false
    
    // The speed at which the emulation runs
    var speed = 500.0
    
    // The peripherals
    let graphics : Graphics
    let sound : Sound
    let keyboard : Keyboard
    
    // The queue we are calculating on so we don't have it on the main graphics thread
    let dispatchQueue = DispatchQueue(label: "nl.indev.chip8", attributes: []);
    
    // Mapping every opcode to a closure
    
    // Using the following info in the naming of the methods, the first part is the assembly name that would happen, after the underscore what is being moved, copied or checked
    // ADDR - A 12-bit value, the lowest 12 bits of the instruction
    // N  - A nibble (4-bit) value
    // BYTE a byte
    // V - a register
    // I - the I (address) register
    // DT - delay timer
    // ST - sound timer
    // K - keyboard button
    // F - Reference to the hexidecimal font in memory
    
    // Since we are checking on the AND value, order here is important

    lazy var mapping : [Opcode] = {
        
        return [
            
            // LD_V_I (Reads from memory location I and stores it in registers V0 to V(x))
            Opcode(code: 0xF065, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                
                for currentRegister in 0 ..< registerX
                {
                    // Get the byte from memory
                    let memoryByte = self.memory[Int(self.I) + currentRegister]
                    
                    // Store it in current register
                    self.V[currentRegister] = memoryByte
                }
            }),
            
            // LD_I_V (Stores the registers v0 to v(x) starting in memory beginning at location I)
            Opcode(code: 0xF055, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                
                for currentRegister in 0 ..< registerX
                {
                    // Get byte from register
                    let registerByte = self.V[currentRegister]
                    
                    // Store it in memory
                    self.memory[Int(self.I) + currentRegister] = registerByte
                }
            }),
            
            // LD_B_V (Stores the binary decimal representation of the value of register V in I)
            Opcode(code: 0xF033, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                var valueX = self.V[registerX]
                
                // With the binary decimal representation (unpacked) every single digit of a number is stored in a seperate byte
                // Number can be max three digits long (8 bits)
                for i in (0 ..< 2).reversed()
                {
                    // Getting the current smallest digit of the whole number
                    let currentValue = valueX % 10
                    
                    // Determine where to store
                    let index = Int(self.I) + i
                    
                    // Store it
                    self.memory[index] = currentValue
                    
                    // Divide by ten so in the next run the second smallest digit is the new smallest digit
                    valueX /= 10
                }
            }),
            
            // LD_F_V (I is set to the address of the corresponding font block representing the value in register V)
            Opcode(code: 0xF029, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                let valueX = self.V[registerX]
                
                // Get the memory offset for this hex number (a single font consists of 5 bytes)
                let memoryOffset = Chip8.FontMemoryLocation + UInt16(valueX * 5)
                
                // And point to the beginning of the font
                self.I = memoryOffset
            }),
            
            // ADD_I_V (I and the register are added and stored in I)
            Opcode(code: 0xF01E, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                self.I = self.I + UInt16(self.V[registerX])
            }),
            
            // LD_ST_V (Set the soundTimer to the value in register V)
            Opcode(code: 0xF018, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                self.soundTimer = self.V[registerX]
            }),
            
            // LD_DT_V (Set the delayTimer to the value in register V)
            Opcode(code: 0xF015, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                self.delayTimer = self.V[registerX]
            }),
            
            // LD_V_K  (Set the register V to the value of the keypress by the keyboard (will wait for keypress))
            Opcode(code: 0xF00A, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                
                var pressedKey : Int8 = -1
                
                // Keep listening for the pressed key until we have it
                repeat {
                    pressedKey = self.keyboard.currentKey
                } while(pressedKey == -1 && self.isRunning)
                
                // And store that key (only if we stopped because of key press, not because of ending the current interpretation)
                if(pressedKey != -1)
                {
                    self.V[registerX] = UInt8(pressedKey)
                }
            }),
            
            // LD_V_DT (Set the register V to the value in delay timer)
            Opcode(code: 0xF007, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                self.V[registerX] = self.delayTimer
            }),
            
            // SKNP_V (Skips the next instruction if the key which represents the valine in register V is not pressed)
            Opcode(code: 0xE0A1, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                let valueX = Int8(self.V[registerX])
                
                if valueX != self.keyboard.currentKey
                {
                    self.pc += 2
                }
            }),
            
            // SKP_V (Skips the next instruction if the key which represents the value in register V is pressed)
            Opcode(code: 0xE09E, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                let valueX = Int8(self.V[registerX])
                
                if valueX == self.keyboard.currentKey
                {
                    self.pc += 2
                }
            }),
            
            // DRW_V_V_N (Draw sprite of length N on memory address I on coordinates of the passed registers VF is set on collision)
            Opcode(code: 0xD000, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                let registerY = Int(arg & 0x00F0) >> 4
                
                let valueX = self.V[registerX]
                let valueY = self.V[registerY]
                
                let spriteSize = UInt16(arg & 0x000F)
                
                let start = Int(self.I)
                let end = Int(self.I + spriteSize)
                
                // Get the part of the memory with the sprite
                let memorySlice = self.memory[start..<end]
                
                // Draw the graphics
                
                // Returns wether the "cleared a pixel while drawing" flag should be true
                if self.graphics.draw(sprite: memorySlice, x: valueX, y: valueY)
                {
                    self.V[0xF] = 1
                }
                else
                {
                    self.V[0xF] = 0
                }
            }),
            
            // RND_V_BYTE (Generates a random byte value which then AND is applied to that value based on the byte parameter and placed in the register V)
            Opcode(code: 0xC000, callback: { arg in
                let random = UInt8(arc4random_uniform(256))
                
                let registerX = Int(arg & 0x0F00) >> 8
                let value = UInt8(arg & 0x00FF)

                self.V[registerX] = random & value
            }),
            
            // JP_V0_ADDR (Jump to the address of ADDR + V0)
            Opcode(code: 0xB000, callback: { arg in
                let value0 = self.V[0];
                self.pc = UInt16(value0) + (arg & 0x0FFF)
            }),
            
            // LD_I_ADDR (The I register is set with the ADDR)
            Opcode(code: 0xA000, callback: { arg in
                self.I = arg & 0x0FFF
            }),
            
            // SNE_V_V (Skip next instruction if the first register does not match the second register)
            Opcode(code: 0x9000, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                let registerY = Int(arg & 0x00F0) >> 4
                
                let valueX = self.V[registerX]
                let valueY = self.V[registerY]
                
                if(valueX != valueY)
                {
                    self.pc += 2
                }
            }),

            // SHL_V (Shift the first register left by one the flag will containt the MSB before the shift
            Opcode(code: 0x800E, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                let valueX = self.V[registerX]
                
                // Set the flag
                let msb = UInt8((valueX >= 128) ? 1 : 0)
                self.V[0xF] = msb
                
                // Shift
                self.V[registerX] = valueX << 1
            }),
            
            // SUBN_V_V (Subtract the first register from the second register and store the result in the first register, borrow flag is set when there is no borrow)
            Opcode(code: 0x8007, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                let registerY = Int(arg & 0x00F0) >> 4
                
                let valueX = self.V[registerX]
                let valueY = self.V[registerY]
                
                var result = Int(valueY) - Int(valueX)
                
                self.V[0xF] = (result < 0) ? 0 : 1
                
                if result < 0
                {
                    result += 256
                }
                
                self.V[registerX] = UInt8(result)
            }),
            
            // SHR_V (Shift the register x register right by one the flag will contain the LSB before the shift
            Opcode(code: 0x8006, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                let valueX = self.V[registerX]
                
                // Set the flag
                let lsb = valueX & 0x1
                self.V[0xF] = lsb
                
                // Shift
                self.V[registerX] = valueX >> 1
            }),
            
            // SUB_V_V (Subtract the second register from the first and store result in first register, borrow flag is set when there is no borrow)
            Opcode(code: 0x8005, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                let registerY = Int(arg & 0x00F0) >> 4
                
                let valueX = self.V[registerX]
                let valueY = self.V[registerY]
                
                var result = Int(valueX) - Int(valueY)
                
                self.V[0xF] = (result < 0) ? 0 : 1
                
                if result < 0
                {
                    result += 256
                }
                
                self.V[registerX] = UInt8(result)
            }),
            
            // ADD_V_V (Add two registers and store result in first register carry flag is set)
            Opcode(code: 0x8004, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                let registerY = Int(arg & 0x00F0) >> 4
                
                let valueX = self.V[registerX]
                let valueY = self.V[registerY]
                
                // Determine overflowed value
                let sum = Int(valueX) + Int(valueY)
                
                // Set the flag if needed
                self.V[0xF] = (sum > 255) ? 1 : 0
                
                // Store wrapped value
                self.V[registerX] = UInt8(Int(sum) % 256)
            }),
            
            // XOR_V_V (XOR two registers and store result in first register)
            Opcode(code: 0x8003, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                let registerY = Int(arg & 0x00F0) >> 4
                
                let valueX = self.V[registerX]
                let valueY = self.V[registerY]
                
                self.V[registerX] = valueX ^ valueY
            }),
            
            // AND_V_V (AND two registers and store result in first register)
            Opcode(code: 0x8002, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                let registerY = Int(arg & 0x00F0) >> 4
                
                let valueX = self.V[registerX]
                let valueY = self.V[registerY]
                
                self.V[registerX] = valueX & valueY
            }),
            
            // OR_V_V (OR two registers and store result in first register)
            Opcode(code: 0x8001, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                let registerY = Int(arg & 0x00F0) >> 4
                
                let valueX = self.V[registerX]
                let valueY = self.V[registerY]
                
                self.V[registerX] = valueX | valueY
            }),
            
            // LD_V_V (copy register to another register)
            Opcode(code: 0x8000, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                let registerY = Int(arg & 0x00F0) >> 4
                
                self.V[registerX] = self.V[registerY]
            }),
            
            // ADD_V_BYTE (add value to register v)
            Opcode(code: 0x7000, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                let value = UInt8(arg & 0x00FF)
                let currentValue = self.V[registerX]

                // Adding the value, but wrapping around since we can't store more in a byte
                let newValue = currentValue &+ value

                self.V[registerX] = newValue
            }),
            
            // LD_V_BYTE (set register with value)
            Opcode(code: 0x6000, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                let value = UInt8(arg & 0x00FF)
                
                self.V[registerX] = value;
            }),
            
            // SE_V_V (skip next instruction if register equals other register)
            Opcode(code: 0x5000, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                let registerY = Int(arg & 0x00F0) >> 4
                
                if(self.V[registerX] == self.V[registerY])
                {
                    self.pc += 2
                }
            }),

            // SNE_V_BYTE (skip next instruction if register does not equals value)
            Opcode(code: 0x4000, callback: { arg in
                let registerX = Int(arg & 0x0F00) >> 8
                let value = UInt8(arg & 0x00FF)
                
                if(self.V[registerX] != value)
                {
                    self.pc += 2
                }
            }),

            // SE_V_BYTE (skip next instruction if register equals value)
            Opcode(code: 0x3000, callback: { arg in
                let register = Int(arg & 0x0F00) >> 8
                let value = UInt8(arg & 0x00FF)
                
                if(self.V[register] == value)
                {
                    self.pc += 2
                }
            }),
            
            // CALL_ADDR (call address on subroutine)
            Opcode(code: 0x2000, callback: { arg in
                // Increment stack
                self.sp += 1
                
                // Place current address on the stack
                self.stack[Int(self.sp)] = self.pc

                // And jump to passed address
                self.pc = UInt16(arg & 0x0FFF)
            }),
            
            // JP_ADDR (jump to a memory address)
            Opcode(code: 0x1000, callback: { arg in
                self.pc = arg & 0x0FFF
            }),

            // RET (return from a subroutine)
            Opcode(code: 0x00EE, callback: { arg in
                // Set the program counter to the current item on the stack
                self.pc = self.stack[Int(self.sp)]
                
                // Decrement stack pointer
                self.sp -= 1
            }),
            
            // CLS (clear the display)
            Opcode(code: 0x00E0, callback: { arg in
                self.graphics.clear()
            })
        ]
    }()

    // Hooks up the peripherals to the Chip8 system
    init(graphics: Graphics, sound: Sound, keyboard: Keyboard)
    {
        self.graphics = graphics
        self.sound = sound
        self.keyboard = keyboard

        self.reset()
    }
    
    /**
     * Load data into memory
     */
    func load(_ rom: Data, autostart : Bool = true)
    {
        // Keep track of the rom
        self.rom = rom
        
        // Change to a state in which we can load
        self.stopLoop()
        self.reset()
        
        // Converting NSData to byte array
        var bytesArray = [UInt8](repeating: 0, count: rom.count)
        (rom as NSData).getBytes(&bytesArray, length: rom.count)
        
        // Getting each byte and moving it to the correct spot in memory
        for (index, byte) in bytesArray.enumerated()
        {
            let indexInMemory = Chip8.RomLocation + UInt16(index)
            self.memory[Int(indexInMemory)] = byte
        }
        
        if autostart
        {
            self.startLoop()
        }
    }
    
    /**
     * Reloads the current rom again 
     */
    func resetRom(_ autostart: Bool)
    {
        self.load(self.rom!, autostart: autostart)
    }
    
    /**
     * Resets everything to the beginning state
     */
    func reset()
    {
        // Make sure the loop is stopped
        self.stopLoop()
        
        // And reset
        self.memory = [UInt8](repeating: 0, count: Chip8.MemorySize)
        self.V = [UInt8](repeating: 0, count: Chip8.RegisterSize)
        self.I = 0
        self.stack = [UInt16](repeating: 0, count: Chip8.StackSize)
        self.sp = UInt8(self.stack.count - 1)
        self.sp = 0
        self.pc = Chip8.RomLocation
        self.delayTimer = 0
        self.soundTimer = 0
        
        // And load the fonts
        self.loadFonts()
        
        // Clear the screen
        self.graphics.clear()
    }

    /**
     * Starts the main loop
     */
    func startLoop()
    {
        self.isRunning = true

        // Start the timer loop
        self.timerLoop()
        
        // And cpu cycle loop
        self.CPUCycleLoop()
    }
    
    /**
     * Stops the loop
     */
    func stopLoop()
    {
        self.isRunning = false
    }
    
    /**
     * Changes the speed of the emulation
     */
    func changeSpeed(_ speed: Double)
    {
        self.speed = speed;
    }
    
    /**
     * Loads the font sprite information in memory
     */
    fileprivate func loadFonts()
    {
        for (index, fontByte) in Graphics.FontSpriteData.enumerated()
        {
            let indexWithOffset = Int(UInt16(index) + Chip8.FontMemoryLocation)
            self.memory[indexWithOffset] = fontByte
        }
    }
    
    /**
     * The countdown timer loop
     */
    fileprivate func timerLoop()
    {
        if self.isRunning
        {
            // Make sure the timers countdown
            self.countdownTimers()
            
            // Make sound if needed
            self.makeNoise()

            // And call self recursively after that delay
            delay(1.0 / (60.0 * Settings.sharedSettings.renderSpeed), closure: self.timerLoop)
        }

    }
    
    /**
     * The CPU Cycle loop
     */
    fileprivate func CPUCycleLoop()
    {
        // Determine if we should continue the loop
        if self.isRunning
        {
            // Handle the next instruction
            self.tickInstruction()

            // And call self recursively after that delay
            delay(1.0 / (1000 * Settings.sharedSettings.renderSpeed), closure: self.CPUCycleLoop)
        }
    }
    
    /**
     * Wrapper for the dispatch_after to make it a bit more easy
     */
    func delay(_ delay: Double, closure: @escaping ()->()) {
        // Calculate delay
        let delay = DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
        
        // And add to queue
        self.dispatchQueue.asyncAfter(deadline: delay, execute: closure)
    }
    
    /**
     * Counts the timers in the system down
     */
    fileprivate func tickInstruction()
    {
        // Get current block to run from memory everything which is stored in blocks of two bytes containing both the opcode and "parameters"
        let memoryBlock = UInt16(self.memory[Int(self.pc)]) << 8 | UInt16(self.memory[Int(self.pc + 1)])

//        print("Memory value at PC \(self.pc) \(String(memoryBlock, radix: 16))")
        
        // Increment the program counter
        self.pc+=2
        
        // Try every possible opcode to see if the current memory block hold that opcode
        for (mapping) in self.mapping
        {
            let opcode = mapping.code

            // Determine if the current opcode matches with the information in the memory block
            if (memoryBlock & opcode) == opcode
            {
                
//                print("Memory matches opcode \(String(opcode, radix: 16))")

                // Call the closure
                mapping.callback(memoryBlock)

                // No need to check further
                break
            }
        }
    }

    /**
     * Determines if the attached sound peripherals should make noise
     */
    fileprivate func makeNoise()
    {
        if self.soundTimer > 0 && !self.isPlayingSound
        {
            self.sound.startBeep()
            self.isPlayingSound = true
        }
        else if self.soundTimer <= 0 && self.isPlayingSound
        {
            self.sound.stopBeep()
            self.isPlayingSound = false
        }
    }

    /**
     * Counts the timers in the system down
     */
    fileprivate func countdownTimers()
    {
        // Decrement the delay timer
        if self.delayTimer > 0
        {
            self.delayTimer -= 1
        }
        
        // And the sound timer
        if self.soundTimer > 0
        {
            self.soundTimer -= 1
        }
    }
    
}
