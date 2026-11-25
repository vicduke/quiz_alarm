/// Where the app's server side lives. All three values are public by
/// design: the key only lets the app talk to the project, and the server's
/// own rules decide what a signed-in person may do. No secret belongs here.
library;

class ServerConfig {
  /// Accounts, question bank and progress (Supabase).
  static const String supabaseUrl = 'https://zsplxgvizlndnofsokxw.supabase.co';
  static const String supabaseKey =
      'sb_publishable_bE2OwJPR9O9mhzRi-HVPLw_lh7G7-LB';

  /// Sent with problem reports. Keep equal to "version" in pubspec.yaml.
  static const String appVersion = '1.0.5+6';

  /// The AI server (writes questions, tutor, marking of typed answers).
  static const String apiUrl =
      'https://jarvis-norys.austriaeast.cloudapp.azure.com/brainwake';

  /// The legal pages (hosted with the admin site; public).
  static const String termsUrl = 'https://brainoclock.onrender.com/terms.html';
  static const String privacyUrl =
      'https://brainoclock.onrender.com/privacy.html';

  /// Where the app is downloaded and updated from.
  static const String downloadUrl =
      'https://brainoclock.onrender.com/#download';

  /// The Google Cloud "web" client the server checks Google sign-ins
  /// against (a public identifier, not a secret).
  static const String googleWebClientId =
      '241246067706-qb4el2s60fvgnv3qn09i4qltlulk0jn4.apps.googleusercontent.com';
}
