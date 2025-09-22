import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var email: String = ""
    @State private var zipcode: String = ""
    @State private var rememberMe: Bool = true

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Logo and Title
                VStack(spacing: 20) {
                    Image("Logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)

                    Text("KLMunchery")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .padding(.top, 80)

                Spacer()

                // Login Form
                VStack(spacing: 20) {
                    Text("Welcome Back!")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    VStack(spacing: 16) {
                        TextField("Enter your zipcode", text: $zipcode)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.default)
                            .font(.body)

                        TextField("Enter your email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .font(.body)
                    }

                    HStack {
                        Text("Remember Me")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Spacer()

                        Toggle("", isOn: $rememberMe)
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                    }
                    .padding(.horizontal)

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
                .padding(.horizontal, 30)

                Spacer()
            }
            .navigationBarHidden(true)
            .background(Color(.systemBackground))
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func login() {
        appState.login(email: email, zipcode: zipcode)
    }
}

#Preview {
    LoginView()
        .environmentObject(AppState())
}
