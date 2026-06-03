enum AvatarAnimationState {
  idle('Idle'),
  loading('Loading'),
  speaking('Speaking');

  final String trackName;
  const AvatarAnimationState(this.trackName);
}
