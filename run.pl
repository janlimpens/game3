#! /usr/bin/env perl

use v5.38;

use lib '.';
use lib 'lib';

use ECS;
use DDP;
use Game3::Processor::HelloWorld;

my $ecs = ECS->new();
my $proc = Game3::Processor::HelloWorld->new(priority => 1);
my $world = ECS::World->new();



my $component = bless {}, 'Component';

$world->add_processor($proc);
$world->create_entity($component);
$world->process();

p $ecs;
p $proc;
p $world