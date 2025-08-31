import SwiftUI

// MARK: - Limmi Text Field Component
// A reusable text field component with consistent styling using DesignSystem

public struct LimmiTextField: View {
    
    // MARK: - Properties
    
    public let title: String
    public let placeholder: String
    @Binding public var text: String
    public let isSecure: Bool
    public let keyboardType: UIKeyboardType
    public let textContentType: UITextContentType?
    public let validationState: ValidationState
    
    // MARK: - Initializer
    
    public init(
        title: String,
        placeholder: String = "",
        text: Binding<String>,
        isSecure: Bool = false,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        validationState: ValidationState = .neutral
    ) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.isSecure = isSecure
        self.keyboardType = keyboardType
        self.textContentType = textContentType
        self.validationState = validationState
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
            // Title
            if !title.isEmpty {
                Text(title)
                    .font(DesignSystem.bodyTextSmall)
                    .fontWeight(.medium)
                    .foregroundColor(titleColor)
            }
            
            // Text Field
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(DesignSystem.bodyText)
            .foregroundColor(DesignSystem.pureBlack)
            .padding(.horizontal, DesignSystem.spacingM)
            .frame(height: DesignSystem.inputHeight)
            .background(DesignSystem.pureWhite)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .cornerRadius(DesignSystem.cornerRadius)
            .keyboardType(keyboardType)
            .textContentType(textContentType)
            
            // Validation Message
            if let message = validationMessage {
                Text(message)
                    .font(DesignSystem.captionText)
                    .foregroundColor(validationColor)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var titleColor: Color {
        switch validationState {
        case .error:
            return .red
        case .success:
            return DesignSystem.secondaryBlue
        case .neutral:
            return DesignSystem.pureBlack
        }
    }
    
    private var borderColor: Color {
        switch validationState {
        case .error:
            return .red
        case .success:
            return DesignSystem.primaryYellow
        case .neutral:
            return DesignSystem.secondaryBlue
        }
    }
    
    private var borderWidth: CGFloat {
        switch validationState {
        case .error, .success:
            return 2
        case .neutral:
            return DesignSystem.borderWidth
        }
    }
    
    private var validationMessage: String? {
        switch validationState {
        case .error(let message):
            return message
        case .success(let message):
            return message
        case .neutral:
            return nil
        }
    }
    
    private var validationColor: Color {
        switch validationState {
        case .error:
            return .red
        case .success:
            return DesignSystem.secondaryBlue
        case .neutral:
            return DesignSystem.secondaryBlue
        }
    }
}

// MARK: - Validation State

public enum ValidationState: Equatable {
    case neutral
    case success(String)
    case error(String)
    
    public static func == (lhs: ValidationState, rhs: ValidationState) -> Bool {
        switch (lhs, rhs) {
        case (.neutral, .neutral):
            return true
        case (.success(let lhsMessage), .success(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

// MARK: - Text Field Variants

public struct LimmiTextFieldVariants {
    
    /// Standard text field
    public static func standard(
        title: String,
        placeholder: String = "",
        text: Binding<String>
    ) -> LimmiTextField {
        LimmiTextField(
            title: title,
            placeholder: placeholder,
            text: text
        )
    }
    
    /// Email text field
    public static func email(
        title: String = "Email",
        placeholder: String = "Enter your email",
        text: Binding<String>
    ) -> LimmiTextField {
        LimmiTextField(
            title: title,
            placeholder: placeholder,
            text: text,
            keyboardType: .emailAddress,
            textContentType: .emailAddress
        )
    }
    
    /// Password text field
    public static func password(
        title: String = "Password",
        placeholder: String = "Enter your password",
        text: Binding<String>
    ) -> LimmiTextField {
        LimmiTextField(
            title: title,
            placeholder: placeholder,
            text: text,
            isSecure: true,
            textContentType: .password
        )
    }
    
    /// Numeric text field
    public static func numeric(
        title: String,
        placeholder: String = "",
        text: Binding<String>
    ) -> LimmiTextField {
        LimmiTextField(
            title: title,
            placeholder: placeholder,
            text: text,
            keyboardType: .numberPad
        )
    }
}

// MARK: - Preview

struct LimmiTextField_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: DesignSystem.spacingL) {
            LimmiTextFieldVariants.standard(
                title: "Standard Field",
                placeholder: "Enter text here",
                text: .constant("")
            )
            
            LimmiTextFieldVariants.email(
                text: .constant("user@example.com")
            )
            
            LimmiTextFieldVariants.password(
                text: .constant("password123")
            )
            
            LimmiTextField(
                title: "Success Field",
                placeholder: "This field is valid",
                text: .constant("Valid input"),
                validationState: .success("Great job!")
            )
            
            LimmiTextField(
                title: "Error Field",
                placeholder: "This field has an error",
                text: .constant("Invalid input"),
                validationState: .error("Please fix this error")
            )
        }
        .padding(DesignSystem.spacingL)
        .background(DesignSystem.backgroundYellow)
        .previewLayout(.sizeThatFits)
    }
}
