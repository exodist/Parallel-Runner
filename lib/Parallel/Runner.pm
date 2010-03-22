package Parallel::Runner;
use strict;
use warnings;

use POSIX ();
use Time::HiRes qw/sleep/;
use Carp;

our $VERSION = 0.003;

for my $accessor (qw/ exit_callback iteration_callback pids pid max /) {
    my $sub = sub {
        my $self = shift;
        ($self->{ $accessor }) = @_ if @_;
        return $self->{ $accessor };
    };
    no strict 'refs';
    *$accessor = $sub;
}

sub new {
    my $class = shift;
    my ($max) = shift;
    return bless(
        {
            pids => [],
            pid  => $$,
            max  => $max || 1,
            @_
        },
        $class
    );
}

sub run {
    my $self = shift;
    my ( $code, $force_fork ) = @_;
    croak( "Called run() in child process" )
        unless $self->pid == $$;

    $force_fork = 0 if $self->max > 1;
    return $self->_fork( $code, $force_fork )
        if $force_fork || $self->max > 1;

    return $code->();
}

sub _fork {
    my $self = shift;
    my ( $code, $forced ) = @_;

    # This will block if necessary
    my $tid = $self->get_tid
        unless $forced;

    my $pid = fork();
    if ( $pid ) {
        return $self->tid_pid( $tid, $pid )
            unless $forced;

        until ( waitpid( $pid, &POSIX::WNOHANG )) {
            $self->iteration_callback->()
                if $self->iteration_callback;
            sleep(0.10);
        }
        return;
    }

    # Make sure this new process does not wait on the previous process's children.
    $self->pids([]);

    my @return = $code->();
    $self->exit_callback->( @return ) if $self->exit_callback;
    exit;
}

sub get_tid {
    my $self = shift;
    my $existing = $self->pids;
    while ( 1 ) {
        for my $i ( 1 .. $self->max ) {
            if ( my $pid = $existing->[$i] ) {
                my $out = waitpid( $pid, &POSIX::WNOHANG );
                $existing->[$i] = undef
                    if ( $pid == $out || $out < 0 );
            }
            return $i unless $existing->[$i];
        }
        $self->iteration_callback->()
            if $self->iteration_callback;
        sleep(0.10);
    }
}

# Get or set the pid for a tid.
sub tid_pid {
    my $self = shift;
    my ( $tid, $pid ) = @_;
    $self->pids->[$tid] = $pid if $pid;
    return $self->pids->[$tid];
}

sub finish {
    my $self = shift;
    my ( $timeout, $timeoutsub ) = @_;
    my %pids = map { $_ => 1 } grep { $_ } @{ $self->pids };
    my $counter = 0;
    while ( values %pids ) {
        for my $pid ( keys %pids ) {
            delete $pids{$pid}
                if waitpid( $pid, &POSIX::WNOHANG );
        }
        sleep(0.10);
        $counter += 0.10;
        $self->iteration_callback->()
            if $self->iteration_callback;
        last if $timeout and $counter >= $timeout;
    }
    $timeoutsub->() if $timeout
                   && $timeoutsub
                   && $counter >= $timeout;
    $self->pids([]);
    1;
}

sub killall {
    my $self = shift;
    my ( $sig ) = @_;
    for my $pid ( grep { $_ } @{ $self->pids }) {
        warn time . " - Killing: $pid - $sig\n";
        kill( $sig, $pid );
    }
}

sub DESTROY {
    my $self = shift;
    return unless $self->pid == $$
               && $self->pids
               && @{ $self->pids };
    warn <<EOT;
Parallel::Runner object destroyed without first calling finish(), This will
terminate all your child processes. This either means you forgot to call
finish() or your parent process has died.
EOT
    return $self->finish if $^O eq 'MSWin32';

    $self->finish( 1, sub {
        $self->killall(15);
        $self->finish(4, sub {
            $self->killall(9);
            $self->finish(10);
        });
    });
}

1;

=pod

=head1 NAME

Parallel::Runner - An object to manage running things in parallel processes.

=head1 DESCRIPTION

There are several other modules to do this, you probably want one of them. This
module exists as a super specialised parallel task manager. You create the
object with a proces limit and callbacks for what to do while waiting for a
free process slot, as well as a callback for what a process shoudl do just
before exiting.

You must explicetly call $runner->finish() when you are done. If the runner is
destroyed before it's children are finished a warning will be generated and
your child processes will be killed, by force if necessary.

If you specify a maximum of 1 then no forking will occur, and run() will block
until the coderef returns. You can force a fork by providing a boolean true
value as the second argument to run(), this will force the runner to fork
before running the coderef, however run() will still block until it the child
exits.

=head1 SYNOPSYS

    #!/usr/bin/perl
    use strict;
    use warnings;
    use Parallel::Runner;

    my $runner = Parallel::Runner->new(4);
    $runner->run( sub { ... } );
    $runner->run( sub { ... } );
    $runner->run( sub { ... } );
    $runner->run( sub { ... } );

    # This will block until one of the previous 4 finishes
    $runner->run( sub { ... } );

    # Do not forget this.
    $runner->finish;

=head1 CONSTRUCTOR

=over 4

=item $runner = $class->new( $max, $accessor => $value, ... );

Create a new instance of Parallel::Runner. $accessor can be anything listed
under the ACCESSORS section. $max should be the maximum number of processes
allowed, defaults to 1.

=back

=head1 ACCESSORS

These are simple accessors, provididng an argument sets the accessor to that
argument, no argument it simply returns the current value.

=over 4

=item $val = $runner->exit_callback( \&callback )

Codref to call just before a child exits (called within child)

=item $val = $runner->iteration_callback( $newval )

Coderef to call multiple times in a loop while run() is blocking waiting for a
process slot.

=item $val = $runner->pids([ $pid1, $pid2, ... ])

Arrayref of child pids

=item $val = $runner->pid( $newval )

pid of the parent process

=item $val = $runner->max( $newval )

Maximum number of children

=back

=head1 OBJECT METHODS

=over 4

=item run( $code )

=item run( $code, $force_fork )

Run the specified code in a child process. Blocks if no free slots are
available. Force fork can be used to force a fork when max is 1, however it
will still block until the child exits.

=item get_tid()

Get the number of a free process slot, will block if none are available.

=item tid_pid( $pid )

Get the process slot number for a pid.

=item finish()

=item finish( $timeout )

=item finish( $timeout, $timeoutcallback )

Wait for all children to finish, then clean up after them. If a timeout is
specified it will return after the timeout regardless of wether or not children
have all exited. If there is a timeout call back then that code will be run
upon timeout just before the method returns.

NOTE: DO NOT LET YOUR RUNNER BE DESTROYED BEFORE FINISH COMPLETES WITHOUT A
TIMEOUT.

the runner will kill all childred, possibly with force if your runner is
destroyed with children still running, or not waited on.

=item killall( $sig )

Send all children the specified kill signal.

=item DESTROY()

Automagically called when the object is destroyed. If called while children are
running it will forcefully clean up after you as follows:

1) Sends an ugly warning.

2) Will first give all your children 1 second to complete.

3) Sends kill signal 15 to all children then waits up to 4 seconds.

4) Sends kill signal 9 to any remaining children then waits up to 10 seconds

5) Gives up and returns

=back

=head1 AUTHORS

Chad Granum L<exodist7@gmail.com>

=head1 COPYRIGHT

Copyright (C) 2010 Chad Granum

Parallel-Runner is free software; Standard perl licence.

Parallel-Runner is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the license for more details.
