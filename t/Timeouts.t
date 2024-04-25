#!/usr/bin/perl
use strict;
use warnings;

use Test2::V0 -target => 'Parallel::Runner';
use Child qw/child/;

sub timed_fork {
    my ($count) = @_;
    my $pid = fork;
    return $pid if $pid;
    sleep $count;
    exit;
}

ok(my $one = $CLASS->new(1), "Created one");
isa_ok($one, $CLASS);

my $fast_child = child {};
ok($fast_child, "Created a fast child");
$one->children($fast_child);

ok(
    lives {
        local $SIG{ALRM} = sub { die("fast child took too long") };
        alarm 5;
        $one->finish;
        alarm 0;
    },
    "reaping"
);

$one->max(2);
$one->children(child { sleep 10 });
$one->children(child { sleep 10 });
like(
    dies {
        local $SIG{ALRM} = sub { die("alarm") };
        alarm 5;
        $one->run(sub { 1 });
        alarm 0;
    },
    qr/alarm/,
    "Timed out"
);

$one->children(child { sleep 10 });
$one->children(child { sleep 10 });
ok(
    lives {
        local $SIG{ALRM} = sub { die("alarm") };
        alarm 20;
        my $start = time;
        $one->run(sub { 1 });
        ok(time - $start > 3, "was blocking");
        alarm 0;
    },
    "Subprocess did not exit"
);
$one->finish;

$one->max(3);
ok(
    lives {
        local $SIG{ALRM} = sub { die("alarm") };
        alarm 5;
        $one->run(sub { sleep 15 });
        $one->run(sub { sleep 15 });
        $one->run(sub { sleep 15 });
        alarm 0;
    },
    "3 processes w/o waiting"
);

like(
    dies {
        local $SIG{ALRM} = sub { die("alarm") };
        alarm 5;
        $one->run(sub { sleep 1 });
        alarm 0
    },
    qr/alarm/,
    "Blocked"
);

ok(
    lives {
        local $SIG{ALRM} = sub { die("alarm") };
        alarm 30;
        my $start = time;
        $one->run(sub { sleep 1 });
        ok(1,                 "Eventually ran");
        ok(time - $start > 5, "Blocked a while");
        alarm 0
    },
    "Blocked"
);
$one->finish;

$one->max(1);

ok(
    lives {
        local $SIG{ALRM} = sub { die("alarm") };
        alarm 5;
        $one->run(sub { 1 });
        alarm 0;
        ok(1, "Not blocked");
    },
    "Not blocked"
);

my $temp;
like(
    dies {
        local $SIG{ALRM} = sub { die("alarm") };
        alarm 5;
        $one->run(sub { $temp = 'inside'; sleep 10 });
        alarm 0;
    },
    qr/alarm/,
    "Run w/o fork"
);
ok(!$one->children, "no new pids");
is($temp, 'inside', "Ran, but did not fork");
$one->finish;

$temp = 'fork';
like(
    dies {
        local $SIG{ALRM} = sub { die("alarm") };
        alarm 5;
        $one->run(sub { $temp = 'no fork'; sleep 10 }, 1);
        alarm 0;
    },
    qr/alarm/,
    "fork but wait"
);
is($temp, 'fork', "Forked");
$one->finish;

ok(
    lives {
        local $SIG{ALRM} = sub { die("alarm") };
        alarm 15;
        my $start = time;
        $one->run(sub { sleep 7 }, 1);
        ok(time - $start > 4, "fork finished");
        alarm 0;
    },
    "fork finished"
);

$one->finish;
done_testing;
