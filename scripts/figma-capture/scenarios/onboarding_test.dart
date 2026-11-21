// Figma capture of onboarding: first-run setup, the start menu and its
// steps, the /join paste screen and the startup lock screen.
import 'harness.dart';
import 'onboarding_setup.dart';
import 'onboarding_start.dart';

void main() => figmaScenes('onboarding',
    [...setupScenes, ...startScenes, ...joinScenes, ...lockScenes]);
