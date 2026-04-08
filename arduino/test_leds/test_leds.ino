int red = 10;
int yellow = 9;
int green = 8;

void setup() {
  pinMode(red, OUTPUT);
  pinMode(yellow, OUTPUT);
  pinMode(green, OUTPUT);
}

void loop() {
  digitalWrite(red, HIGH);
  delay(500);
  digitalWrite(red, LOW);

  digitalWrite(yellow, HIGH);
  delay(500);
  digitalWrite(yellow, LOW);

  digitalWrite(green, HIGH);
  delay(500);
  digitalWrite(green, LOW);
}
