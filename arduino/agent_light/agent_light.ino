// Pin assignments: {red, yellow, green} for each group
const int GROUP_PINS[4][3] = {
  {4, 3, 2},    // Group 1
  {7, 6, 5},    // Group 2
  {10, 9, 8},   // Group 3
  {13, 12, 11}  // Group 4
};

const int NUM_GROUPS = 4;

void allOffGroup(int group) {
  for (int i = 0; i < 3; i++) {
    digitalWrite(GROUP_PINS[group][i], LOW);
  }
}

void setup() {
  for (int g = 0; g < NUM_GROUPS; g++) {
    for (int i = 0; i < 3; i++) {
      pinMode(GROUP_PINS[g][i], OUTPUT);
      digitalWrite(GROUP_PINS[g][i], LOW);
    }
  }
  Serial.begin(9600);
}

void loop() {
  if (Serial.available() >= 2) {
    char groupChar = Serial.read();
    char cmd = Serial.read();

    int group = groupChar - '1';  // '1'-'4' -> 0-3
    if (group < 0 || group >= NUM_GROUPS) return;

    allOffGroup(group);

    switch (cmd) {
      case 'R': digitalWrite(GROUP_PINS[group][0], HIGH); break;
      case 'Y': digitalWrite(GROUP_PINS[group][1], HIGH); break;
      case 'G': digitalWrite(GROUP_PINS[group][2], HIGH); break;
      case 'O': break;
    }
  }
}
