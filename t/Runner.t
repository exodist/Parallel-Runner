#!/usr/bin/perl
use strict;
use warnings;

use Test::More;
use Test::Exception::LessClever;

my $CLASS = 'Parallel::Runner';
use_ok( $CLASS );

can_ok( $CLASS, qw/new exit_callback iteration_callback pids pid max/);

ok( my $one = $CLASS->new, "Created one" );
isa_ok( $one, $CLASS );
is( $one->max, 1, "got max" );
is( $one->pid, $$, "Stored pid" );
is_deeply(
    $one,
    {
        max  => 1,
        pid  => $$,
        pids => [],
    },
    "Built properly"
);

is( $one->tid_pid( 1 ), undef, "No pid for tid 1" );
is( $one->tid_pid( 1, 55 ), 55, "set pid for tid" );
is( $one->tid_pid( 1 ), 55, "Has pid" );
is( $one->tid_pid( 2, 56 ), 56, "set pid for tid" );
is( $one->tid_pid( 3, 57 ), 57, "set pid for tid" );
is_deeply( $one->pids, [ undef, 55, 56, 57 ], "Got pids" );
$one->finish;

throws_ok {
    my $one = $CLASS->new( 2 );
    $one->pid( 0.5 );
    $one->run( sub { 1 });
} qr/Called run\(\) in child process/,
  "Do not run in fork";

my $ran = 0;
my $iter_callback = sub { $ran++ };
$one = $CLASS->new(2, iteration_callback => $iter_callback );
ok( $one->iteration_callback, "Stored callback" );

$one->run( sub { sleep 5 });
$one->run( sub { sleep 5 });
ok( !$ran, "No waiting yet" );
$one->run( sub { 1 });
ok( $ran > 20, "Iterated while waiting" );
$one->finish;

$ran = 0;
$one->max(1);
ok( !$ran, "No waiting yet" );
$one->run( sub { sleep 5 }, 1);
ok( $ran > 20, "Iterated while waiting" );
$one->finish;

my ( $read, $write );
unless( pipe( $read, $write )) {
    skip "Pipe not available: $!", 1;
    done_testing;
    exit;
}

my $ecallback = sub { print $write "ran\n" };

$one = $CLASS->new( 2, exit_callback => $ecallback );
$one->run( sub { 1 });
$one->finish;

my $data;
lives_ok {
    local $SIG{ALRM} = sub { die( 'alarm' )};
    alarm 5;
    $data = <$read>;
    alarm 0;
} "read from pipe";
is( $data, "ran\n", "exit callback ran" );

done_testing;
