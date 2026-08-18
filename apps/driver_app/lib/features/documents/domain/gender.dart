/// Gender, collected on the Photo and Name document step.
enum Gender {
  male('Male'),
  female('Female'),
  other('Other');

  const Gender(this.label);

  final String label;
}
