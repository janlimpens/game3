use v5.38;
use Object::Pad;

class Game3::Processor::HelloWorld
{
    use lib '.';
    use ECS;

    method process
    {
        say "Hello, World!";
    }

    apply ECS::Processor;
}
