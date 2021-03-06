//
// Project «InputMask»
// Created by Jeorge Taflanidi
//


import Foundation
import UIKit


/**
 ### MaskedTextFieldDelegateListener
 
 Allows clients to obtain value extracted by the mask from user input.
 
 Provides callbacks from listened UITextField.
 */
@objc public protocol MaskedTextFieldDelegateListener: UITextFieldDelegate {
    
    /**
     Callback to return extracted value and to signal whether the user has complete input.
     */
    @objc optional func textField(
        _ textField: UITextField,
        didFillMandatoryCharacters complete: Bool,
        didExtractValue value: String
    )
    
}


/**
 ### MaskedTextFieldDelegate
 
 UITextFieldDelegate, which applies masking to the user input.
 
 Might be used as a decorator, which forwards UITextFieldDelegate calls to its own listener.
 */
@IBDesignable
open class MaskedTextFieldDelegate: NSObject, UITextFieldDelegate {

    open weak var listener: MaskedTextFieldDelegateListener?
    open var onMaskedTextChangedCallback: ((_ textField: UITextField, _ value: String, _ complete: Bool) -> ())?
    
    @IBInspectable open var primaryMaskFormat: String
    @IBInspectable open var autocomplete: Bool
    @IBInspectable open var autocompleteOnFocus: Bool
    
    open var affineFormats: [String]
    open var affinityCalculationStrategy: AffinityCalculationStrategy
    open var customNotations: [Notation]
    
    open var primaryMask: Mask {
        return try! Mask.getOrCreate(withFormat: primaryMaskFormat, customNotations: customNotations)
    }
    
    public init(
        primaryFormat: String = "",
        autocomplete: Bool = true,
        autocompleteOnFocus: Bool = true,
        affineFormats: [String] = [],
        affinityCalculationStrategy: AffinityCalculationStrategy = .wholeString,
        customNotations: [Notation] = [],
        onMaskedTextChangedCallback: ((_ textInput: UITextInput, _ value: String, _ complete: Bool) -> ())? = nil
    ) {
        self.primaryMaskFormat = primaryFormat
        self.autocomplete = autocomplete
        self.autocompleteOnFocus = autocompleteOnFocus
        self.affineFormats = affineFormats
        self.affinityCalculationStrategy = affinityCalculationStrategy
        self.customNotations = customNotations
        self.onMaskedTextChangedCallback = onMaskedTextChangedCallback
        super.init()
    }
    
    public override convenience init() {
        // Interface Builder support
        self.init(primaryFormat: "")
    }
    
    /**
     Maximal length of the text inside the field.
     
     - returns: Total available count of mandatory and optional characters inside the text field.
     */
    open var placeholder: String {
        return primaryMask.placeholder
    }
    
    /**
     Minimal length of the text inside the field to fill all mandatory characters in the mask.
     
     - returns: Minimal satisfying count of characters inside the text field.
     */
    open var acceptableTextLength: Int {
        return primaryMask.acceptableTextLength
    }
    
    /**
     Maximal length of the text inside the field.
     
     - returns: Total available count of mandatory and optional characters inside the text field.
     */
    open var totalTextLength: Int {
        return primaryMask.totalTextLength
    }
    
    /**
     Minimal length of the extracted value with all mandatory characters filled.
     
     - returns: Minimal satisfying count of characters in extracted value.
     */
    open var acceptableValueLength: Int {
        return primaryMask.acceptableValueLength
    }
    
    /**
     Maximal length of the extracted value.
     
     - returns: Total available count of mandatory and optional characters for extracted value.
     */
    open var totalValueLength: Int {
        return primaryMask.totalValueLength
    }
    
    @discardableResult
    open func put(text: String, into field: UITextField, autocomplete putAutocomplete: Bool? = nil) -> Mask.Result {
        let autocomplete: Bool = putAutocomplete ?? self.autocomplete
        let mask: Mask = pickMask(forText: CaretString(string: text), autocomplete: autocomplete)
        
        let result: Mask.Result = mask.apply(
            toText: CaretString(string: text, caretPosition: text.endIndex),
            autocomplete: autocomplete
        )
        
        field.text = result.formattedText.string
        field.cursorPosition = result.formattedText.string.distance(
            from: result.formattedText.string.startIndex,
            to: result.formattedText.caretPosition
        )
        
        notifyOnMaskedTextChangedListeners(forTextField: field, result: result)
        return result
    }
    
    open func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        return listener?.textFieldShouldBeginEditing?(textField) ?? true
    }
    
    open func textFieldDidBeginEditing(_ textField: UITextField) {
        if autocompleteOnFocus && (textField.text ?? "").isEmpty {
            let result: Mask.Result = put(text: "", into: textField, autocomplete: true)
            notifyOnMaskedTextChangedListeners(forTextField: textField, result: result)
        }
        listener?.textFieldDidBeginEditing?(textField)
    }
    
    open func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        return listener?.textFieldShouldEndEditing?(textField) ?? true
    }
    
    open func textFieldDidEndEditing(_ textField: UITextField) {
        listener?.textFieldDidEndEditing?(textField)
    }
    
    @available(iOS 10.0, *)
    open func textFieldDidEndEditing(_ textField: UITextField, reason: UITextField.DidEndEditingReason) {
        listener?.textFieldDidEndEditing?(textField, reason: reason)
    }
    
    open func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        let result: Mask.Result
        if isDeletion(inRange: range, string: string) {
            result = deleteText(inRange: range, inTextField: textField)
        } else {
            result = modifyText(inRange: range, inTextField: textField, withText: string)
        }
        notifyOnMaskedTextChangedListeners(forTextField: textField, result: result)
        return false
    }
    
    open func textFieldShouldClear(_ textField: UITextField) -> Bool {
        let shouldClear = listener?.textFieldShouldClear?(textField) ?? true
        if shouldClear {
            let result: Mask.Result = put(text: "", into: textField, autocomplete: false)
            notifyOnMaskedTextChangedListeners(forTextField: textField, result: result)
        }
        return shouldClear
    }
    
    open func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        return listener?.textFieldShouldReturn?(textField) ?? true
    }
    
    open func isDeletion(inRange range: NSRange, string: String) -> Bool {
        return 0 < range.length && 0 == string.count
    }
    
    open func deleteText(inRange range: NSRange, inTextField field: UITextField) -> Mask.Result {
        let updatedText: String = replaceCharacters(inText: field.text ?? "", range: range, withCharacters: "")
        let caretPosition: String.Index = updatedText.index(updatedText.startIndex, offsetBy: range.location)
        
        let mask: Mask = pickMask(
            forText: CaretString(string: updatedText, caretPosition: caretPosition),
            autocomplete: false
        )
        
        let result: Mask.Result = mask.apply(
            toText: CaretString(string: updatedText, caretPosition: caretPosition),
            autocomplete: false
        )
        
        field.text = result.formattedText.string
        field.cursorPosition = range.location
        
        return result
    }
    
    open func modifyText(inRange range: NSRange, inTextField field: UITextField, withText text: String) -> Mask.Result {
        let updatedText: String = replaceCharacters(inText: field.text ?? "", range: range, withCharacters: text)
        let caretPosition: String.Index = updatedText.index(
            updatedText.startIndex,
            offsetBy: range.location + text.count
        )
        
        let mask: Mask = pickMask(
            forText: CaretString(string: updatedText, caretPosition: caretPosition),
            autocomplete: autocomplete
        )
        
        let result: Mask.Result = mask.apply(
            toText: CaretString(string: updatedText, caretPosition: caretPosition),
            autocomplete: autocomplete
        )
        
        field.text = result.formattedText.string
        field.cursorPosition = result.formattedText.string.distance(
            from: result.formattedText.string.startIndex,
            to: result.formattedText.caretPosition
        )
        
        return result
    }
    
    open func replaceCharacters(inText text: String, range: NSRange, withCharacters newText: String) -> String {
        if 0 < range.length {
            let result = NSMutableString(string: text)
            result.replaceCharacters(in: range, with: newText)
            return result as String
        } else {
            let result = NSMutableString(string: text)
            result.insert(newText, at: range.location)
            return result as String
        }
    }
    
    open func pickMask(forText text: CaretString, autocomplete: Bool) -> Mask {
        guard !affineFormats.isEmpty
        else { return primaryMask }
        
        let primaryAffinity: Int = affinityCalculationStrategy.calculateAffinity(ofMask: primaryMask, forText: text, autocomplete: autocomplete)
        
        var masksAndAffinities: [MaskAndAffinity] = affineFormats.map { (affineFormat: String) -> MaskAndAffinity in
            let mask = try! Mask.getOrCreate(withFormat: affineFormat, customNotations: customNotations)
            let affinity = affinityCalculationStrategy.calculateAffinity(ofMask: mask, forText: text, autocomplete: autocomplete)
            return MaskAndAffinity(mask: mask, affinity: affinity)
            }.sorted { (left: MaskAndAffinity, right: MaskAndAffinity) -> Bool in
                return left.affinity > right.affinity
        }
        
        var insertIndex: Int = -1
        
        for (index, maskAndAffinity) in masksAndAffinities.enumerated() {
            if primaryAffinity >= maskAndAffinity.affinity {
                insertIndex = index
                break
            }
        }
        
        if (insertIndex >= 0) {
            masksAndAffinities.insert(MaskAndAffinity(mask: primaryMask, affinity: primaryAffinity), at: insertIndex)
        } else {
            masksAndAffinities.append(MaskAndAffinity(mask: primaryMask, affinity: primaryAffinity))
        }
        
        return masksAndAffinities.first!.mask
    }
    
    open func notifyOnMaskedTextChangedListeners(forTextField textField: UITextField, result: Mask.Result) {
        listener?.textField?(textField, didFillMandatoryCharacters: result.complete, didExtractValue: result.extractedValue)
        onMaskedTextChangedCallback?(textField, result.extractedValue, result.complete)
    }
    
    private struct MaskAndAffinity {
        let mask: Mask
        let affinity: Int
    }
    
    /**
     Workaround to support Interface Builder delegate outlets.
     
     Allows assigning ```MaskedTextFieldDelegate.listener``` within the Interface Builder.
     
     Consider using ```MaskedTextFieldDelegate.listener``` property from your source code instead of
     ```MaskedTextFieldDelegate.delegate``` outlet.
     */
    @IBOutlet public var delegate: NSObject? {
        get {
            return self.listener as? NSObject
        }
        
        set(newDelegate) {
            if let listener = newDelegate as? MaskedTextFieldDelegateListener {
                self.listener = listener
            }
        }
    }
    
}
