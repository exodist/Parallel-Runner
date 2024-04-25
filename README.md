# NAME

Parallel::Runner - An object to manage running things in parallel processes.

# DESCRIPTION

There are several other modules to do this, you probably want one of them. This
module exists as a super specialised parallel task manager. You create the
object with a process limit and callbacks for what to do while waiting for a
free process slot, as well as a callback for what a process should do just
before exiting.

You must explicitly call $runner->finish() when you are done. If the runner is
destroyed before it's children are finished a warning will be generated and
your child processes will be killed, by force if necessary.

If you specify a maximum of 1 then no forking will occur, and run() will block
until the coderef returns. You can force a fork by providing a boolean true
value as the second argument to run(), this will force the runner to fork
before running the coderef, however run() will still block until it the child
exits.

# SYNOPSYS

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

# CONSTRUCTOR

- $runner = $class->new( $max, $accessor => $value, ... );

    Create a new instance of Parallel::Runner. $accessor can be anything listed
    under the ACCESSORS section. $max should be the maximum number of processes
    allowed, defaults to 1.

# ACCESSORS

These are simple accessors, providing an argument sets the accessor to that
argument, no argument it simply returns the current value.

- $val = $runner->data\_callback( \\&callback )

    If this is specified than IPC will be automatically enabled, and the final
    return from each process will be passed into this handler in the main process.
    Due to the way IPC works only strings/numerical data is passed, if you need to
    pass a ref you will need to serialize it yourself before returning it, followed
    by deserializing it in your callback.

    Example:

        # Place to put the accumulated data
        my @accum_data;

        # Create the runner with a callback that pushes the data onto our array.
        $runner = $CLASS->new( 2,
            data_callback => sub {
                my ($data) = @_;
                push @accum_data => $data;
            },
        );

        # 4 processes that return data
        $runner->run( sub { return "foo" });
        $runner->run( sub { return "bar" });
        $runner->run( sub { return "baz" });
        $runner->run( sub { return "bat" });
        $runner->finish;

        # Verify the data (order is not predictable)
        is_deeply(
            [ sort @accum_data ],
            [ sort qw/foo bar baz bat/ ],
            "Got all data returned by subprocesses"
        );

- $val = $runner->exit\_callback( \\&callback )

    Codref to call just before a child exits (called within child)

- $val = $runner->iteration\_delay( $float );

    How long to wait per iterate if nothing has changed.

- $val = $runner->iteration\_callback( $newval )

    Coderef to call multiple times in a loop while run() is blocking waiting for a
    process slot.

- $val = $runner->reap\_callback( $newval )

    Codref to call whenever a pid is reaped using waitpid. The callback sub will be
    passed 3 values The first is the exit status of the child process. The second
    is the pid of the child process. The third used to be the return of waitpid,
    but this is deprecated as [Child](https://metacpan.org/pod/Child) is now used and throws an exception when
    waitpid is not what it should be. The third is simply the pid of the child
    process again. The final argument is the child process object itself.

        $runner->reap_callback( sub {
            my ( $status, $pid, $pid_again, $proc ) = @_;

            # Status as returned from system, so 0 is good, 1+ is bad.
            die "Child $pid did not exit 0"
                if $status;
        });

- @children = $runner->children( @append )

    Returns a list of [Child::Link::Proc](https://metacpan.org/pod/Child%3A%3ALink%3A%3AProc) objects.

- $val = $runner->pid()

    pid of the parent process

- $val = $runner->max( $newval )

    Maximum number of children

# OBJECT METHODS

- run( $code )
- run( $code, $force\_fork )

    Run the specified code in a child process. Blocks if no free slots are
    available. Force fork can be used to force a fork when max is 1, however it
    will still block until the child exits.

- finish()
- finish( $timeout )
- finish( $timeout, $timeoutcallback )

    Wait for all children to finish, then clean up after them. If a timeout is
    specified it will return after the timeout regardless of wether or not children
    have all exited. If there is a timeout call back then that code will be run
    upon timeout just before the method returns.

    NOTE: DO NOT LET YOUR RUNNER BE DESTROYED BEFORE FINISH COMPLETES WITHOUT A
    TIMEOUT.

    the runner will kill all children, possibly with force if your runner is
    destroyed with children still running, or not waited on.

- killall( $sig )

    Send all children the specified kill signal.

- DESTROY()

    Automagically called when the object is destroyed. If called while children are
    running it will forcefully clean up after you as follows:

    1) Sends an ugly warning.

    2) Will first give all your children 1 second to complete.

    Windows) Strawberry fails with processes, so on windows DESTROY will wait as
    long as needed, possibly forever.

    3) Sends kill signal 15 to all children then waits up to 4 seconds.

    4) Sends kill signal 9 to any remaining children then waits up to 10 seconds

    5) Gives up and returns

# FENNEC PROJECT

This module is part of the Fennec project. See [Fennec](https://metacpan.org/pod/Fennec) for more details.
Fennec is a project to develop an extendable and powerful testing framework.
Together the tools that make up the Fennec framework provide a potent testing
environment.

The tools provided by Fennec are also useful on their own. Sometimes a tool
created for Fennec is useful outside the greater framework. Such tools are
turned into their own projects. This is one such project.

- [Fennec](https://metacpan.org/pod/Fennec) - The core framework

    The primary Fennec project that ties them all together.

# AUTHORS

Chad Granum [exodist7@gmail.com](https://metacpan.org/pod/exodist7%40gmail.com)

# COPYRIGHT

Copyright (C) 2010 Chad Granum

Parallel-Runner is free software; Standard perl licence.

Parallel-Runner is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the license for more details.
