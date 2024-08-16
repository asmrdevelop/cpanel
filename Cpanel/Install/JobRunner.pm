package Cpanel::Install::JobRunner;

# cpanel - Cpanel/Install/JobRunner.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Install::JobRunner

=head1 SYNOPSIS

    use Cpanel::Install::JobRunner();

    my $jr = Cpanel::Install::JobRunner->new();

    $jr->dispatch_next() while $jr->get_pending_jobs();

… or try this handy one-liner:

    perl -MCpanel::Install::JobRunner -e'my $jr = Cpanel::Install::JobRunner->new(); $jr->dispatch_next() while $jr->get_pending_jobs()'

=head1 DESCRIPTION

Dispatcher for cPanel & WHM installation jobs.

=head1 TODO

Eventually this should parallelize its tasks so that several child processes
execute these install jobs simultaneously. Under this setup the parent
process would manage the list of tasks, “assigning” them to child processes
as the child processes report availability.

It might also be ideal to distinguish programmatically between “failed”
and “prevented” jobs—i.e., whether a job ran and failed or was prevented
from running by a needed job’s failure.

=head1 SEE ALSO

L<Cpanel::Install::Job> describes how to create a new install job
in this system.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::Install::JobRunner::Logger    ();
use Cpanel::Install::JobRunner::Constants ();
use Cpanel::LoadModule::AllNames          ();
use Cpanel::Set                           ();

use constant {
    _DEBUG => 0,
};

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class.

=cut

sub new ($class) {
    my $job_modules_hr = _load_job_modules();

    _require($_) for values %$job_modules_hr;

    my @job_modules = sort keys %$job_modules_hr;
    _debug( "Jobs:\n" . join( "\n", ( map { "\t$_" } @job_modules ), q<> ) );

    my $logger = Cpanel::Install::JobRunner::Logger->new();

    my %self = (
        succeeded   => {},
        failed      => {},
        job_modules => \@job_modules,
        logger      => $logger,
    );

    return bless \%self, $class;
}

=head2 @jobs = I<OBJ>->get_pending_jobs()

In list context, returns the I<full> module name for all pending jobs.

In scalar context, returns the number of such module names that would
be returned in list context.

=cut

sub get_pending_jobs ($self) {
    return Cpanel::Set::difference(
        $self->{'job_modules'},
        [ keys %{ $self->{'succeeded'} } ],
        [ keys %{ $self->{'failed'} } ],
    );
}

=head2 $yn = I<OBJ>->dispatch_next()

The “workhorse” of this system. It determines the next-available job
to run (if any) and runs it. If that job fails, all dependent jobs
(including dependents of dependents, etc.) are marked as having failed.

Appropriate log messages are generated at the beginning and end of each job.

Returns a boolean that indicates whether any work was done.

=cut

sub dispatch_next ($self) {
    local $@;

    my @pending = $self->get_pending_jobs();

    return 0 if !@pending;

    for my $module_name (@pending) {
        my @needs = $module_name->get_needs();

        if ( my @unmet_needs = grep { !$self->{'succeeded'}{$_} } @needs ) {
            _debug("Skipping $module_name: still needs @unmet_needs");
        }
        else {
            $self->{'logger'}->info( "\n" . $module_name->get_short_name() . ': ' . $module_name->get_description() );

            my $obj = $module_name->new(
                logger => $self->{'logger'},
            );

            my $indent = $self->{'logger'}->create_log_level_indent();

            my $ok = eval {
                local $SIG{'__WARN__'} = sub {
                    $self->{'logger'}->warn( q<> . shift() );
                };

                $obj->run();

                1;
            };

            if ($ok) {
                $self->{'succeeded'}{$module_name} = 1;

                $self->{'logger'}->success( locale()->maketext('Success!') );
            }
            else {
                my $err = $@;

                $self->{'failed'}{$module_name} = $err;

                $self->{'logger'}->error("$err");

                # Assume Z depends on A, and B depends on Z.
                # If A fails, then Z will implicitly fail.
                # And so will B, but we won’t know that until we recognize Z’s
                # implicit failure. So repeat this until we have settled all
                # implicit failures.
                1 while $self->_reap_failures();

                die if $obj->is_critical();
            }

            return 1;
        }
    }

    die "Pending jobs have no path to dependency completion: [@pending]";
}

#----------------------------------------------------------------------

sub _reap_failures ($self) {
    my $reaped = 0;

    for my $module_name ( $self->get_pending_jobs() ) {
        my @needs = $module_name->get_needs();

        if ( my @failed_needs = grep { $self->{'failed'}{$_} } @needs ) {
            $reaped++;

            @failed_needs = map { $_->get_short_name() } @failed_needs;

            my $msg = locale()->maketext( '“[_1]” cannot proceed because it requires [list_and_quoted,_2].', $module_name->get_short_name, \@failed_needs );

            $self->{'failed'}{$module_name} = $msg;

            $self->{'logger'}->error($msg);
        }
    }

    return $reaped;
}

# mocked in tests
sub _require ($path) {
    return require $path;
}

sub _debug {
    print( shift() . "\n" ) if _DEBUG();

    return;
}

sub _load_job_modules {
    my $ns = Cpanel::Install::JobRunner::Constants::JOBS_NAMESPACE();

    return Cpanel::LoadModule::AllNames::get_loadable_modules_in_namespace($ns);
}

1;
