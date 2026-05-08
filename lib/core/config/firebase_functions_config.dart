const String firebaseProjectId = String.fromEnvironment(
  'FIREBASE_PROJECT_ID',
  defaultValue: 'spargo-app',
);

const String firebaseFunctionsRegion = String.fromEnvironment(
  'FIREBASE_FUNCTIONS_REGION',
  defaultValue: 'europe-west3',
);

Uri firebaseFunctionUri(
  String functionName, {
  Map<String, String>? queryParameters,
}) {
  return Uri.https(
    '$firebaseFunctionsRegion-$firebaseProjectId.cloudfunctions.net',
    '/$functionName',
    queryParameters,
  );
}
