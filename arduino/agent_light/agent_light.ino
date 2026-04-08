int red = 10;
int yellow = 9;
int green = 8;

void allOff() {
  digitalWrite(red, LOW);
  digitalWrite(yellow, LOW);
  digitalWrite(green, LOW);
}

void setup() {
  pinMode(red, OUTPUT);
  pinMode(yellow, OUTPUT);
  pinMode(green, OUTPUT);
  Serial.begin(9600);
  allOff();
}

void loop() {
  if (Serial.available() > 0) {
    char cmd = Serial.read();
    allOff();
    switch (cmd) {
      case 'R': digitalWrite(red, HIGH); break;
      case 'Y': digitalWrite(yellow, HIGH); break;
      case 'G': digitalWrite(green, HIGH); break;
      case 'O': break; // off
    }
  }
}
