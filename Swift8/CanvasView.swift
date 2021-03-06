//
//  CanvasView.swift
//  Swift8
//
//  Created by Matthijn Dijkstra on 23/08/15.
//  Copyright © 2015 Matthijn Dijkstra. All rights reserved.
//

import Cocoa

class CanvasView : NSView, Chip8Graphics
{
    // The colors to draw
    var theme = Themes.defaultTheme {
        didSet {
            self.setNeedsDisplay(self.bounds)
        }
    }

    // Calculating how big each pixel should be drawn based on current view size (original screen size is 64 x 32 pixels, which is puny)
    var pixelSize: Int {
        get {
            let widthRatio = Int(self.frame.size.width / 2)
            let heightRatio = Int(self.frame.size.height / 1)
            
            let pixelSize = min(widthRatio, heightRatio) / Graphics.ScreenHeight
            return pixelSize
        }
    }

    // Every bool will light up one pixel if it is true
    var pixels = [Bool](repeating: false, count: Int(Graphics.ScreenWidth * Graphics.ScreenHeight))
    
    // MARK: Chip8Graphics
    
    /**
    * Clear the screen
    */
    func clear()
    {
        self.pixels = [Bool](repeating: false, count: Int(Graphics.ScreenWidth * Graphics.ScreenHeight))
        self.setNeedsDisplay(self.bounds)
    }
    
   /**
    * Storing the data to draw in the correct location
    */
    func draw(sprite data: ArraySlice<UInt8>, x: UInt8, y: UInt8) -> Bool
    {
        var didOverwrite = false
     
        for (index, var spriteByte) in data.enumerated()
        {

            // Every next byte will be drawn one row lower then the previous
            var currentY = y + UInt8(index)
            
            // Wrapping the Y around
            if currentY >= Graphics.ScreenHeight
            {
                currentY = currentY - UInt8(Graphics.ScreenHeight)
            }
            
            // Every bit in the spritedata byte corresponds to one pixel mapping it to the self.pixels array
            for bitIndex in 0 ..< 8
            {
                // Every bit will be drawn on the next column
                var currentX = x &+ UInt8(bitIndex)
                
                // Wrapping the x around
                if currentX >= Graphics.ScreenWidth
                {
                    currentX = currentX - UInt8(Graphics.ScreenWidth)
                }
                
                // Create a byte with only the  the left most bit from this byte to get the current pixel
                let leftMostBit = spriteByte ^ 0b01111111
                
                // Convert the byte to a boolean
                var currentPixel = (leftMostBit >= 128) ? true : false

                // Shift left so the next round we get the new next bit
                spriteByte = spriteByte << 1
                
                // Only draw or clear if the current pixel should be changed
                if currentPixel
                {
                    // Determine the index in the pixels array to change to the new pixel
                    let pixelPosition = ((Int(currentY) * Int(Graphics.ScreenWidth)) + Int(currentX))

                    // When drawing on the same spot twice the pixel gets changed to blank if there is a pixel there
                    if currentPixel == true && self.pixels[pixelPosition] == true
                    {
                        currentPixel = false
                        
                        // Change the didOverwrite flag to reflect that a pixel in this draw session has been overwritten
                        if !didOverwrite
                        {
                            didOverwrite = true
                        }
                    }
                    
                    // Store the new pixel informatio on the correct position
                    self.pixels[pixelPosition] = currentPixel
                }
            }
        }
        
        // Todo: Get the rect for the bounds to update for improved performance
        self.setNeedsDisplay(self.bounds)
        
        
        return didOverwrite
    }
    
    // MARK: NSView drawing
    
    /**
     * Draws on the NSView
     */
    override func draw(_ dirtyRect: NSRect)
    {   
        // Todo: Determine which parts need to be drawn for increased performance instead of drawing all
        self.fillBackgroundInRect(dirtyRect)
        
        // No need to recalculate it every time
        let calculatedPixelSize = self.pixelSize
        
        // Calculate the offsets to make sure the drawing is always centered
        let renderWidth = self.pixelSize * Graphics.ScreenWidth
        let renderHeight = self.pixelSize * Graphics.ScreenHeight
        
        let offsetY = (Int(self.frame.size.height) - renderHeight) / 2
        let offsetX = (Int(self.frame.size.width) - renderWidth) / 2
        
        var colorToDraw = self.theme.backgroundColor
        
        // Iterate over every row
        for y in 0 ..< Int(Graphics.ScreenHeight)
        {
            // And column
            for x in 0 ..< Int(Graphics.ScreenWidth)
            {
                // Get the state for the current pixel
                let pixelIndex = Int(x + (y * Graphics.ScreenWidth))

                let pixelState = self.pixels[pixelIndex]

                // Determine color to draw for this pixel
                colorToDraw = (pixelState) ? self.theme.foregroundColor : self.theme.backgroundColor
                colorToDraw.set()

                // Determine the NSView location to draw, NSView works from bottom left while Chip8 works from top left
                let canvasX = (x * self.pixelSize) + offsetX
                let canvasY = ((Graphics.ScreenHeight * calculatedPixelSize) - (y * calculatedPixelSize) - calculatedPixelSize) + offsetY

                // Making the pixel size a tiny bit smaller, since that looks more cool
                let rectToDraw = CGRect(x: canvasX, y: canvasY, width: calculatedPixelSize - 1, height: calculatedPixelSize - 1)

                // And draw
                rectToDraw.fill()
            }
        }
        
    }
    
    func fillBackgroundInRect(_ rect: NSRect)
    {
        self.theme.backgroundColor.set()
        rect.fill()
    }
    
}
