class NocturneMemoryRootSpec {
  final String name;
  final String uri;

  const NocturneMemoryRootSpec({required this.name, required this.uri});
}

class NocturneMemoryRoots {
  NocturneMemoryRoots._();

  static const List<NocturneMemoryRootSpec> all = <NocturneMemoryRootSpec>[
    NocturneMemoryRootSpec(name: 'identity', uri: 'core://my_user/identity'),
    NocturneMemoryRootSpec(name: 'people', uri: 'core://my_user/people'),
    NocturneMemoryRootSpec(name: 'places', uri: 'core://my_user/places'),
    NocturneMemoryRootSpec(
      name: 'organizations',
      uri: 'core://my_user/organizations',
    ),
    NocturneMemoryRootSpec(
      name: 'preferences',
      uri: 'core://my_user/preferences',
    ),
    NocturneMemoryRootSpec(name: 'interests', uri: 'core://my_user/interests'),
    NocturneMemoryRootSpec(name: 'projects', uri: 'core://my_user/projects'),
    NocturneMemoryRootSpec(name: 'goals', uri: 'core://my_user/goals'),
    NocturneMemoryRootSpec(name: 'habits', uri: 'core://my_user/habits'),
    NocturneMemoryRootSpec(name: 'other', uri: 'core://my_user/other'),
  ];
}
