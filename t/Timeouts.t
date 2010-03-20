#!/usr/bin/perl
use strict;
use warnings;

use Test::More;
use Test::Exception::LessClever;

sub timed_fork {
    my ( $count ) = @_;
    my $pid = fork;
    return $pid if $pid;
    sleep $count;
    exit;
}

my $CLASS = 'Parallel::Runner';
use_ok( $CLASS );
ok( my $one = $CLASS->new( 1 ), "Created one" );
isa_ok( $one, $CLASS );

my $fast_child = fork;
exit unless $fast_child;
ok( $fast_child, "Created a fast child" );
$one->pids([undef, $fast_child]);

lives_ok {
    local $SIG{ ALRM } = sub { die("fast child took too long")};
    alarm 5;
    $one->finish;
    alarm 0;
} "reaping";

$fast_child = fork;
exit unless $fast_child;
waitpid( $fast_child, 0 );
$one->pids([undef, $fast_child]);

ok( $one->pids->[1], "bad pid here" );
lives_ok {
    local $SIG{ ALRM } = sub { die("waited to long for bad pid")};
    alarm 5;
    $one->get_tid;
    alarm 0;
} "wait on bad pid";
is( $one->pids->[0], undef, "no item 0" );
is( $one->pids->[1], undef, "Cleared bad pid" );

$one->max( 3 );
$one->pids([]);
is( $one->get_tid(), 1, "Get first available tid (1)" );
$one->tid_pid( 1, timed_fork( 10 ) );
is( $one->get_tid(), 2, "Get first available tid (2)" );
$one->tid_pid( 2, timed_fork( 10 ) );
is( $one->get_tid(), 3, "Get first available tid (3)" );
$one->tid_pid( 3, timed_fork( 10 ) );

throws_ok {
    local $SIG{ ALRM } = sub { die("alarm")};
    alarm 5;
    $one->get_tid();
    alarm 0;
} qr/alarm/,
  "Timed out";

lives_and {
    local $SIG{ ALRM } = sub { die("alarm")};
    alarm 20;
    my $start = time;
    my $tid = $one->get_tid();
    ok( time - $start > 3, "was blocking" );
    ok( $tid, "Got tid after blocking" );
    alarm 0;
} "Subprocess did not exit";
$one->finish;

lives_ok {
    local $SIG{ ALRM } = sub { die("alarm")};
    alarm 5;
    $one->run( sub { sleep 15 } );
    $one->run( sub { sleep 15 } );
    $one->run( sub { sleep 15 } );
    alarm 0;
} "3 processes w/o waiting" || diag $@;

throws_ok {
    local $SIG{ ALRM } = sub { die("alarm")};
    alarm 5;
    $one->run( sub { sleep 1 });
    alarm 0
} qr/alarm/, "Blocked";

lives_and {
    local $SIG{ ALRM } = sub { die("alarm")};
    alarm 30;
    my $start = time;
    $one->run( sub { sleep 1 });
    ok( 1, "Eventually got a tid" );
    ok( time - $start > 5, "Blocked a while" );
    alarm 0
} "Blocked";
$one->finish;

$one->max(1);

lives_and {
    local $SIG{ ALRM } = sub { die("alarm")};
    alarm 5;
    $one->get_tid();
    alarm 0;
    ok( 1, "Not blocked" );
} "Not blocked";

my $temp;
throws_ok {
    local $SIG{ ALRM } = sub { die("alarm")};
    alarm 5;
    $one->run( sub { $temp = 'inside'; sleep 10 });
    alarm 0;
} qr/alarm/, "Run w/o fork";
ok( ! @{ $one->pids }, "no new pids" );
is( $temp, 'inside', "Ran, but did not fork" );
$one->finish;

$temp = 'fork';
throws_ok {
    local $SIG{ ALRM } = sub { die("alarm")};
    alarm 5;
    $one->run( sub { $temp = 'no fork'; sleep 10 }, 1 );
    alarm 0;
} qr/alarm/, "fork but wait";
is( $temp, 'fork', "Forked" );
$one->finish;

lives_and {
    local $SIG{ ALRM } = sub { die("alarm")};
    alarm 15;
    my $start = time;
    $one->run( sub { sleep 7 }, 1 );
    ok( time - $start > 4, "fork finished" );
    alarm 0;
} "fork finished";

$one->finish;
done_testing;
