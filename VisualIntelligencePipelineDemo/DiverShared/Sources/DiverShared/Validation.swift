import Foundation

public enum Validation {
    public static func isValidURL(_ string: String?) -> Bool {
        guard let string = string else { return false }

        // Use a regular expression to check for a valid URL format.
        // This regex is a common and reasonably effective one.
        let urlRegEx = "^(https|http)://[-a-zA-Z0-9+&@#/%?=~_|!:,.;]*[-a-zA-Z0-9+&@#/%=~_|]"
        let urlTest = NSPredicate(format:"SELF MATCHES %@", urlRegEx)
        
        // First, check if the string matches the URL format.
        guard urlTest.evaluate(with: string) else {
            return false
        }
        
        // Second, try to create a URLComponents object to catch more complex errors.
        guard let components = URLComponents(string: string),
              let _ = components.url else {
            return false
        }
        
        return true
    }
}
