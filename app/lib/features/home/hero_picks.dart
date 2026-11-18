import '../../data/models/models.dart';
import '../../state/app_view_model.dart';

/// What one of the hero's optional picks does, applied the same way from the
/// hero itself and from the demo panel.
///
/// The pickers belong to the hero, so a pick must not behave differently
/// depending on who opened the sheet. The same-value guard lives here for the
/// same reason: re-declaring with the mood that is already live would extend the
/// declaration, which is not what picking it again means. Only the failure
/// feedback stays with the caller: the hero shakes the control it touched, the
/// panel shows a message.
///
/// Each one answers false when the API rejected the change.
Future<bool> applyMoodPick(AppViewModel viewModel, Mood mood) async {
  if (mood == viewModel.myHima?.mood) return true;
  try {
    await viewModel.changeMood(mood);
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> applyDurationPick(AppViewModel viewModel, int minutes) async {
  if (minutes == viewModel.myHima?.durationMin) return true;
  try {
    await viewModel.selectDuration(minutes);
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> applyActivityPick(
  AppViewModel viewModel,
  Activity? activity,
) async {
  if (activity == viewModel.selectedActivity) return true;
  try {
    await viewModel.selectActivity(activity);
    return true;
  } catch (_) {
    return false;
  }
}
