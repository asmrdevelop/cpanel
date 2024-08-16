package Cpanel::MysqlUtils::RemoteMySQL::ActivationJob;

# cpanel - Cpanel/MysqlUtils/RemoteMySQL/ActivationJob.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Time::Local                             ();
use Cpanel::Transaction::File::JSON                 ();
use Cpanel::Transaction::File::JSONReader           ();
use Cpanel::MysqlUtils::RemoteMySQL::ProfileManager ();

=head1 NAME

Cpanel::MysqlUtils::RemoteMySQL::ActivationJob

=head1 SYNOPSIS

    my $job = Cpanel::MysqlUtils::RemoteMySQL::ActivationJob->new();
    $job->start_step('step 1');
    # passing code to do step 1
    $job->done_step('step 1');
    $job->mark_job_done();
    undef $job;

    my $job2 = Cpanel::MysqlUtils::RemoteMySQL::ActivationJob-new();
    $job2->start_step('step 2');
    # failing code to do step 2
    $job2->fail_step('step 2');
    $job2->mark_job_failed();
    undef $job2;



=cut

# Used for mocking in unit tests
sub ACTIVATION_PROGRESS_FILE {
    return Cpanel::MysqlUtils::RemoteMySQL::ProfileManager::_base_dir() . '/activation_in_progress';
}

sub LAST_ACTIVATION_RUN_FILE {
    return Cpanel::MysqlUtils::RemoteMySQL::ProfileManager::_base_dir() . '/last_activation_info';
}

# String placeholders
my $INPROGRESS = 'INPROGRESS';
my $SKIPPED    = 'SKIPPED';
my $FAILED     = 'FAILED';
my $DONE       = 'DONE';

=head1 Methods

=over 8

=item B<new>

Constructor.

Takes the Profile Name as the argument.

=cut

sub new {
    my ( $class, $profile_name ) = @_;

    my $self = bless {
        'progress' => {
            'profile_name' => $profile_name,
            'start_time'   => scalar Cpanel::Time::Local::localtime2timestamp(),
            'status'       => 'INITIALIZING',
            'steps'        => [],
        },
        'step_indexes' => {},
    }, $class;

    $self->_initialize();
    $self->_save();

    return $self;
}

=item B<start_step>

Object method.

Moves the job into progress, and starts tracking the step specified in the job file.

B<Input>: The 'name' of the step to track.
B<Output>: None.

=cut

sub start_step {
    my ( $self, $name ) = @_;

    $self->{'progress'}->{'status'} = $INPROGRESS;
    print "[*] $name …\n";
    my $step = {
        'name'       => $name,
        'status'     => $INPROGRESS,
        'start_time' => scalar Cpanel::Time::Local::localtime2timestamp(),
    };
    $self->{'step_indexes'}->{$name} = scalar @{ $self->{'progress'}->{'steps'} };
    push @{ $self->{'progress'}->{'steps'} }, $step;
    return $self->_save();
}

=item B<done_step>

Object method.

Marks a tracked step as done. It does not check if the step specified is tracked or not atm.

B<Input>: The 'name' of the step to mark as done.
B<Output>: None.

=cut

sub done_step {
    my ( $self, $name ) = @_;

    print "[+] $name … Done\n";
    my $step_index = $self->{'step_indexes'}->{$name};
    $self->{'progress'}->{'steps'}->[$step_index]->{'status'}   = $DONE;
    $self->{'progress'}->{'steps'}->[$step_index]->{'end_time'} = scalar Cpanel::Time::Local::localtime2timestamp();
    return $self->_save();
}

=item B<fail_step>

Object method.

Marks a tracked step as failed. It does not check if the step specified is tracked or not atm.

B<Input>: The 'name' of the step to mark as failed. And a hashref containing the 'error' string to display.
B<Output>: None.

=cut

sub fail_step {
    my ( $self, $name, $error_info ) = @_;

    print "[!] $name … Failed: $error_info->{'error'}\n";
    my $step_index = $self->{'step_indexes'}->{$name};
    $self->{'progress'}->{'steps'}->[$step_index]->{'status'}   = $FAILED;
    $self->{'progress'}->{'steps'}->[$step_index]->{'end_time'} = scalar Cpanel::Time::Local::localtime2timestamp();
    $self->{'progress'}->{'steps'}->[$step_index]->{'error'}    = $error_info->{'error'};
    return $self->_save();
}

=item B<skip_step>

Object method.

Marks a tracked step as skipped. It does not check if the step specified is tracked or not atm.

B<Input>: The 'name' of the step to mark as skipped. And a hashref containing the 'error' string to display.
B<Output>: None.

=cut

sub skip_step {
    my ( $self, $name, $error_info ) = @_;

    print "[!] $name … Skipped: $error_info->{'error'}\n";
    my $step_index = $self->{'step_indexes'}->{$name};
    $self->{'progress'}->{'steps'}->[$step_index]->{'status'}   = $SKIPPED;
    $self->{'progress'}->{'steps'}->[$step_index]->{'end_time'} = scalar Cpanel::Time::Local::localtime2timestamp();
    $self->{'progress'}->{'steps'}->[$step_index]->{'error'}    = $error_info->{'error'};
    return $self->_save();
}

=item B<mark_job_done>

Object method.

Marks the job as done - should be the last thing you call on the job object before undefing it to indicate completion.

B<Input>: None.
B<Output>: None.

The 'inprogress' file is renamed to be the 'last activation' file on completion.
These files are defined by the C<ACTIVATION_PROGRESS_FILE> and C<LAST_ACTIVATION_RUN_FILE> functions.

=cut

sub mark_job_done {
    my $self = shift;
    return $self->_mark_job($DONE);
}

=item B<mark_job_failed>

Object method.

Marks the job as failed - should be the last thing you call on the job object before undefing it to indicate completion.

B<Input>: None.
B<Output>: None.

The 'inprogress' file is renamed to be the 'last activation' file on completion.
These files are defined by the C<ACTIVATION_PROGRESS_FILE> and C<LAST_ACTIVATION_RUN_FILE> functions.

=cut

sub mark_job_failed {
    my $self = shift;
    return $self->_mark_job($FAILED);
}

=item B<get_progress>

Class method.

Return a hashref containing details about the current running job (tracked in C<ACTIVATION_PROGRESS_FILE>),
and the last finished job (tracked in C<LAST_ACTIVATION_RUN_FILE>).

=cut

sub get_progress {
    my $class = shift;

    my $job_in_progress  = Cpanel::Transaction::File::JSONReader->new( path => ACTIVATION_PROGRESS_FILE() )->get_data();
    my $last_job_details = Cpanel::Transaction::File::JSONReader->new( path => LAST_ACTIVATION_RUN_FILE() )->get_data();
    return {
        'job_in_progress'  => ref $job_in_progress eq 'HASH'  ? $job_in_progress  : undef,
        'last_job_details' => ref $last_job_details eq 'HASH' ? $last_job_details : undef,
    };
}

sub _mark_job {
    my ( $self, $status ) = @_;

    print "\n[" . ( $status eq $DONE ? '+' : '!' ) . "] MySQL profile activation " . lc($status) . ".\n";
    $self->{'progress'}->{'status'}   = $status;
    $self->{'progress'}->{'end_time'} = scalar Cpanel::Time::Local::localtime2timestamp();
    $self->_save();
    $self->{'_transaction_obj'}->close_or_die();
    undef $self->{'_transaction_obj'};
    rename ACTIVATION_PROGRESS_FILE(), LAST_ACTIVATION_RUN_FILE();
    return 1;
}

sub _save {
    my $self = shift;

    $self->{'_transaction_obj'}->set_data( $self->{'progress'} );
    return $self->{'_transaction_obj'}->save_or_die();
}

sub _initialize {
    my $self = shift;

    my $base_dir = Cpanel::MysqlUtils::RemoteMySQL::ProfileManager::_base_dir();
    if ( !-d $base_dir ) {
        require File::Path;
        File::Path::make_path( $base_dir, { 'mode' => 0600 } );
    }
    elsif ( !( ( stat $base_dir )[2] & 044 ) ) {
        chmod 0600, $base_dir;
    }

    $self->{'_transaction_obj'} = Cpanel::Transaction::File::JSON->new(
        path        => ACTIVATION_PROGRESS_FILE(),
        permissions => 0600,
        ownership   => ['root'],
    );

    return 1;
}

=back

=cut

1;
