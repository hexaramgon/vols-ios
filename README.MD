# Volspire

## Auth Setup Guide

After building the project, complete the following manual steps to enable Supabase authentication.

---

### 1. Register the `volspire` URL Scheme in Xcode

This allows Google OAuth to redirect back to the app after sign-in.

1. Open **Volspire.xcodeproj** in Xcode.
2. Select the **Volspire** target in the project navigator.
3. Go to the **Info** tab.
4. Scroll down to **URL Types** and click the **+** button to add a new entry.
5. Fill in the fields:
   - **Identifier**: `com.volspire.auth`
   - **URL Schemes**: `volspire`
   - **Role**: `Editor`
6. The app will now handle URLs like `volspire://auth/callback`.

---

### 2. Add the Sign In with Apple Capability

1. In Xcode, select the **Volspire** target.
2. Go to the **Signing & Capabilities** tab.
3. Click **+ Capability** in the top-left corner.
4. Search for **Sign in with Apple** and double-click it to add.
5. Make sure your **Team** is selected and the provisioning profile supports this capability.
6. If prompted, allow Xcode to update the provisioning profile.

---

### 3. Configure Auth Providers in the Supabase Dashboard

#### Apple Sign In

1. Go to your [Supabase Dashboard](https://supabase.com/dashboard) → select your project.
2. Navigate to **Authentication** → **Providers**.
3. Find **Apple** in the provider list and enable it.
4. Fill in the required fields:
   - **Service ID (Client ID)**: Your Apple Services ID (e.g., `com.volspire.auth`). Create one at [Apple Developer → Certificates, Identifiers & Profiles → Identifiers](https://developer.apple.com/account/resources/identifiers/list) → click **+** → select **Services IDs**.
   - **Secret Key**: Generate a key at [Apple Developer → Keys](https://developer.apple.com/account/resources/authkeys/list) → click **+** → enable **Sign in with Apple** → download the `.p8` file. Paste the contents here.
   - **Team ID**: Found at the top-right of your Apple Developer account page.
   - **Key ID**: Shown after creating the key above.
5. Set the **Authorized redirect URI** from Supabase (shown in the provider config) as a **Return URL** in your Apple Services ID configuration on the Apple Developer portal.
6. Click **Save**.

#### Google OAuth

1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Select or create a project.
3. Navigate to **APIs & Services** → **Credentials**.
4. Click **+ Create Credentials** → **OAuth client ID**.
5. Select **iOS** as the application type.
6. Enter your **Bundle ID** (e.g., `com.volspire.app`).
7. Click **Create** and note the **Client ID**.
8. Now go back to your [Supabase Dashboard](https://supabase.com/dashboard) → **Authentication** → **Providers**.
9. Find **Google** and enable it.
10. Enter the **Client ID** and **Client Secret** from Google Cloud Console.
11. The **Authorized redirect URI** shown by Supabase must be added in Google Cloud Console under your OAuth client's **Authorized redirect URIs**.
12. Click **Save** in both Supabase and Google Cloud Console.