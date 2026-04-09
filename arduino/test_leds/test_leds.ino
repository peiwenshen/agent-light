const int GROUP_PINS[4][3] = {
  {4, 3, 2},    // Group 1
  {7, 6, 5},    // Group 2
  {10, 9, 8},   // Group 3
  {13, 12, 11}  // Group 4
};

void setup() {
  for (int g = 0; g < 4; g++) {
    for (int i = 0; i < 3; i++) {
      pinMode(GROUP_PINS[g][i], OUTPUT);
      digitalWrite(GROUP_PINS[g][i], LOW);
    }
  }
}

void loop() {
  for (int g = 0; g < 4; g++) {
    for (int i = 0; i < 3; i++) {
      digitalWrite(GROUP_PINS[g][i], HIGH);
      delay(300);
      digitalWrite(GROUP_PINS[g][i], LOW);
    }
  }
}
