import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var email: String = ""
    @State private var zipcode: String = ""
    @State private var rememberMe: Bool = true

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 40) {
                    // Logo and Title
                    VStack(spacing: 20) {
                        Image("Logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)

                        Text("KLMunchery")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    .padding(.top, 60)

                    // Login Form
                    VStack(spacing: 24) {
                        Text("Welcome Back!")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        VStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Zipcode")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                TextField("Enter your zipcode", text: $zipcode)
                                    .textFieldStyle(.roundedBorder)
                                    .keyboardType(.default)
                                    .font(.body)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                TextField("Enter your email", text: $email)
                                    .textFieldStyle(.roundedBorder)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .font(.body)
                            }
                        }

                        HStack {
                            Text("Remember Me")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Spacer()

                            Toggle("", isOn: $rememberMe)
                                .toggleStyle(SwitchToggleStyle(tint: .blue))
                        }

                        Button(action: login) {
                            Text("Get Started")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.blue, .blue.opacity(0.8)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(12)
                                .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .disabled(email.isEmpty && zipcode.isEmpty)
                        .opacity(email.isEmpty && zipcode.isEmpty ? 0.6 : 1.0)
                    }
                    .padding(.horizontal, 32)

                    Spacer(minLength: 40)
                }
                .frame(minHeight: geometry.size.height)
            }
        }
        .background(Color(.systemBackground))
    }

    private func login() {
        appState.login(email: email, zipcode: zipcode)
    }
}

#Preview {
    LoginView()
        .environmentObject(AppState())
}
