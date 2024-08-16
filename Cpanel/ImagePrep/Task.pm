
# cpanel - Cpanel/ImagePrep/Task.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Task;

use cPstrict;
use Carp ();
use Cpanel::Imports;
use Cpanel::Context           ();
use Cpanel::ImagePrep::Common ();
use Cpanel::Slurper           ();

=head1 NAME

Cpanel::ImagePrep::Task

=head1 SYNOPSIS

Use this module as the base class for snapshot preparation tasks, and
define your implementations for description, type, pre, and post as
_description, _type, _pre, and _post:

  package Cpanel::ImagePrep::Task::Mine;

  use parent 'Cpanel::ImagePrep::Task'

  sub _description { ... }
  sub _type { ... }
  sub _pre { ... }
  sub _post { ... }

Normally this module would then be automatically loaded by the C<snapshot_prep>
and C<post_snapshot> utilities.

If you have a reason to, you may also instantiate and use it directly:

  my $mine = Cpanel::ImagePrep::Task::Mine->new();

  $mine->pre();
  # and/or
  $mine->post();

  # And then check which services need to be restarted
  my $need_restart = $mine->need_restart();
  for my $service (@$need_restart) {
      ...
  }

Or this module can be used an instance that provides access to constant values
used to report outcomes of pre and post in subclasses:

  use Cpanel::ImagePrep::Task ();

  my $constants = Cpanel::ImagePrep::Task->new();
  .............( $constants->PRE_POST_OK );
  .............( $constants->PRE_POST_FAILED );
  .............( $constants->PRE_POST_NOT_APPLICABLE );

=cut

# Return values for use in the 'pre' and 'post' functions.
use constant PRE_POST_OK             => 1;
use constant PRE_POST_FAILED         => 0;    # You can use this, but throwing an exception is preferable
use constant PRE_POST_NOT_APPLICABLE => -1;

=head2 new()

Constructor

=cut

sub new {
    my ($package) = @_;
    my $self      = bless {}, $package;

    # Validate subclass implementation
    if ( $package ne __PACKAGE__ ) {
        $self->type() =~ /^(?:both|repair only|non-repair only)$/ or die sprintf q{Implementation error: Invalid type '%s' specified in package '%s'}, $self->type(), $package;
    }

    return $self;
}

=head2 type()

Subclass must provide the _type() method as the implementation for type().

This is a simple attribute accessor with a fixed value per class.

The valid values are 'non-repair only', 'repair only', and 'both'.

=over

=item * 'non-repair only': Only include this task when doing snapshot preparation
and post actions. This should be the normal type for most new tasks.

=item * 'repair only': UNUSUAL - Only include this task when the 'pre' and 'post' stages
are being done as part of the same process (regenerate_tokens). This means that the
task is not something we expect to ever be needed as part of snapshot preparation.

=item * 'both': UNUSUAL - For snapshot preparation, include this task in the separate
'pre' and 'post' stages. For repair (regenerate_tokens), include this task
in the combined 'pre' and 'post' stages.

=back

B<WARNING:> Do not use the C<repair only> or C<both> types unless you understand the risk
of data loss this entails.

=cut

sub type {
    my ($self) = @_;
    return $self->_type();
}

sub _type { die 'must implement _type' }

=head2 description()

Subclass must provide a _description() method as the implementation
for description().

This is a simple attribute accessor with a fixed value per class.

It is a multiline human-readable description of the task, for display
in list output.

=cut

sub description {
    my ($self) = @_;
    return $self->_description();
}

sub _description { die 'must implement _description' }

=head2 pre()

Subclass must provide the _pre() method as the implementation for pre().

The routine to run on the origin server during snapshot
preparation. This is where server-specific details should
be cleaned out. In some cases, this will render services
unusable until post is run, which is OK. Must return 1 on
success, -1 if not applicable, and either return 0 or throw
an exception on failure.

=cut

sub pre {
    my ($self) = @_;
    $self->common->regular_logmsg( sprintf( 'Starting %s pre ...', $self->task_name ) );
    return $self->_pre();
}

sub _pre { die 'must implement _pre' }

=head2 post()

Subclass must provide the _post() method as the implementation for post().

The routine to run on the deployed instance to regenerate the
deleted credentials or tokens and get the affected service
ready to be started again. Must return 1 on success, -1 if not
applicable, and either return 0 or throw an exception on failure.

=cut

sub post {
    my ($self) = @_;
    $self->{post_called} = 1;
    $self->common->regular_logmsg( sprintf( 'Starting %s post ...', $self->task_name ) );
    return $self->_post();
}

sub _post { die 'must implement _post' }

=head2 deps()

Subclass may optionally provide the _deps() method as an implementation for deps().

If provided, it should return a list of dependencies (other task names). This will
be used to determine the order in which tasks are run.

If not provided, a list containing 'ipaddr_and_hostname' is used. Almost everything
should depend on this task.

=cut

sub deps {
    my ($self) = @_;
    return $self->_deps();
}

sub _deps { return qw(ipaddr_and_hostname); }

=head2 before()

Subclass may optionally provide the _before() method as an implementation for
before().

If provided, it should return a list of other task names which should be ordered
to run after this task.

=cut

sub before {
    my ($self) = @_;
    return $self->_before();
}

sub _before { return; }

=head2 need_restart($add)

Optionally, specify a service name $add to add it to the restart list.

Returns an array ref of service names that need to be restarted in
connection with this change. These are added to the list after post()
is called.

Throws an exception if called before post().

=cut

sub need_restart {
    my ( $self, $add ) = @_;
    die "need_restart was called without post being called" if !$self->{post_called};    # could also happen if subclass inappropriately overrides non-underscore post method
    $self->{need_restart} ||= [];
    if ( defined $add ) {
        push @{ $self->{need_restart} }, $add;
    }
    return $self->{need_restart};
}

=head2 common()

Get an instance of Cpanel::ImagePrep::Common

=cut

my $common;

sub common {
    $common ||= Cpanel::ImagePrep::Common->new();
    return $common;
}

=head2 loginfo($message)

Output a $logger->info() message prefixed with the name of the task.

=cut

sub loginfo {
    my ( $self, $message ) = @_;

    return $self->common->regular_logmsg( sprintf( '%s - %s', $self->task_name, $message ) );
}

=head2 task_name()

Returns the short name of the task. For example, for Cpanel::ImagePrep::Task::exim_srs_secret.pm,
the task name is C<exim_srs_secret>.

=cut

sub task_name {
    my ($self) = @_;
    return ( ( split /::/, ref($self) )[-1] );
}

=head2 should_run_for_stages()

Given a hash ref with keys 'pre' and/or 'post' and a true value for each indicating
that the stage is active for this run, returns whether the task should run for that
stage or combination of stages.

This translates the behavior as follows:

'non-repair only': Only run if this is the pre stage alone or the post stage alone.

'repair-only': Only run if stages are pre & post together.

'both': Run regardless of whether the stage is pre, post, or pre & post together.

=cut

sub should_run_for_stages {
    my ( $self, $stages ) = @_;

    Cpanel::Context::must_be_list();

    if ( $self->{manual_skip} ) {
        return ( 0, 'Skipped (requested)' );
    }

    if ( -e $self->_flag_file ) {
        my $skip_type = Cpanel::Slurper::read( $self->_flag_file );
        if ( $skip_type eq 'requested' ) {
            return ( 0, 'Skipped (requested in prep)' );
        }
        return ( 0, 'Skipped (already done)' );
    }

    if ( $self->type() eq 'repair only' ) {    # A run for both the pre and post stages together is considered "repair". Outside of that, "repair only" tasks should be skipped.
        if ( !$stages->{pre} || !$stages->{post} ) {
            return ( 0, 'Unnecessary (repair only)' );
        }
        return ( 1, '' );
    }
    elsif ( $self->type() eq 'non-repair only' ) {    # For non-repair only tasks, it's quite important to skip them in repair mode, because they could undo configurations set by the server administrator.
        if ( $stages->{pre} && $stages->{post} ) {
            return ( 0, 'Unnecessary (non-repair only)' );
        }
        return ( 1, '' );
    }
    elsif ( $self->type() eq 'both' ) {
        return ( 1, '' );
    }

    die 'invalid type: ' . $self->type();
}

sub manual_skip {
    my ($self) = @_;

    $self->{manual_skip} = 1;
    Cpanel::Slurper::write( $self->_flag_file, 'requested' );
    return;
}

sub _flag_file {
    my ($self) = @_;
    return Cpanel::ImagePrep::Common::FLAG_DIR . '/' . $self->task_name;
}

sub write_flag_file {
    my ($self) = @_;
    return Cpanel::Slurper::write( $self->_flag_file, Cpanel::ImagePrep::Common::instance_id() );
}

sub is_plugin {
    return 0;
}

1;
