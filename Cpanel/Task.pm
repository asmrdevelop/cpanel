package Cpanel::Task;

# cpanel - Cpanel/Task.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::FileUtils::TouchFile ();
use Cpanel::Version              ();
use Cpanel::Time                 ();
use Cpanel::TimeHiRes            ();
use Cpanel::Server::Type         ();

our $VERSION_DIR = "/var/cpanel/version";

sub runtask ($pkg) {
    say qq[Running Task $pkg];
    return $pkg->new->perform ? 0 : 1;
}

sub new ($proto) {

    my $class = ref $proto || $proto;

    my $internal_name_cr = $class->can('_INTERNAL_NAME');

    my $self = {
        'display-name'      => undef,
        'internal-name'     => $internal_name_cr && $internal_name_cr->(),
        'summary'           => undef,
        'dependencies'      => [],
        'only-perform-once' => undef
    };

    bless $self, $class;

    return $self;
}

sub get_display_name ($self) {

    my $name = $self->{'display-name'};

    if ( !$name ) {
        $name = $self->get_internal_name();
    }

    return $name;
}

sub set_display_name ( $self, $name ) {
    $self->{'display-name'} = $name;
    return 1;
}

sub get_internal_name ($self) {
    return $self->{'internal-name'};
}

sub set_internal_name ( $self, $name ) {
    $self->{'internal-name'} = $name;
    return 1;
}

sub get_summary ($self) {
    my $summary = $self->{'summary'};

    if ( !$summary ) {
        $summary = $self->get_internal_name();
    }

    return $summary;
}

sub set_summary ( $self, $summary ) {
    return $self->{'summary'} = $summary;
}

sub get_dependencies ($self) {

    return $self->{'dependencies'};
}

sub add_dependencies ( $self, @deps ) {
    push $self->{'dependencies'}->@*, @deps;

    return;
}

sub enable_only_perform_once ($self) {

    $self->{'only-perform-once'} = 1;

    return;
}

sub disable_only_perform_once ($self) {

    $self->{'only-perform-once'} = undef;

    return;
}

sub only_perform_once ($self) {

    return defined $self->{'only-perform-once'};
}

sub version_file ($self) {

    return '/var/cpanel/version/' . $self->get_internal_name();
}

sub already_performed ($self) {

    return;
}

sub perform ($self) {

    return 1;
}

sub undo ($self) {

    return;
}

sub create_history_msg ($self) {

    my @log_line;

    push @log_line, $self->get_internal_name();
    push @log_line, Cpanel::Version::get_version_text();
    push @log_line, Cpanel::Time::time2condensedtime();

    my $msg = join ":", @log_line;

    return $msg;
}

sub dnsonly ($self) {
    return Cpanel::Server::Type::is_dnsonly();
}

sub did_already ( $self, %opts ) {
    my $lock = $VERSION_DIR . '/cpanel' . $opts{version};
    return -e $lock ? 1 : 0;
}

# Mark as done
sub mark_did_once ( $self, %opts ) {

    my $lock = $VERSION_DIR . '/cpanel' . $opts{version};

    if ( !Cpanel::FileUtils::TouchFile::touchfile($lock) ) {
        $self->_warn("Failed to touch cpanel $opts{version} version file");

        # we should probably exit there.. but to preserve previous behaviour continue
        #   with the risk to perform the action more than once
    }
    return 1;
}

sub do_once ( $self, %opts ) {

    return unless $opts{version} && $opts{code} && ref $opts{code} eq 'CODE';

    my $lock = $VERSION_DIR . '/cpanel' . $opts{version};
    return if -e $lock;

    $self->mark_did_once(%opts);

    say "Running Task: “$opts{'version'}”.";

    my $start_time = Cpanel::TimeHiRes::time();
    my $ret        = eval { $opts{code}->(); };
    my $end_time   = Cpanel::TimeHiRes::time();

    $self->_warn($@) if $@;

    my $exec_time = sprintf( "%.3f", ( $end_time - $start_time ) );
    say "Completed Task: “$opts{'version'}” in $exec_time second(s).";

    return $ret;
}

sub _warn ( $self, $msg ) {

    require Cpanel::Term::ANSIColor::Solarize;
    warn "$0 - " . Cpanel::Term::ANSIColor::Solarize::colored( ['yellow'], "Warning:" ) . " " . $msg . "\n";

    return;
}

1;

__END__

=pod

=head1 NAME

Cpanel::Task - Base class for Tasks run by /usr/local/cpanel/scripts/taskrun.

=head1 SYNOPSIS

package Cpanel::Task::MyTask;

use base qw( Cpanel::Task );

sub new {
    my $proto = shift;
    my $self = $proto->SUPER::new;

    $self->set_internal_name( 'mytask' );

    return $self;
}

sub perform( $self ) {

    # do something

    return 1;
}


=head1 DESCRIPTION

This module serves as a base class for Tasks.

The implementation listed in the synopsis would qualify as a minimal implementation.  Existing Tasks in /usr/local/cpanel/install can be used for futher education.


=head1 METHODS

This class is not intended to be used directly, but instead should be used as a base class for other modules.  The methods below provide the mechanism for derived classes to communicate with the base class.

=head2 new

Class method for creating a new Cpanel::Task.

=head2 get_internal_name / set_internal_name

Accessors for the internal name property of the Task.  This property must be set by derived classes.

=head2 get_display_name / set_display_name

Accessors for the display name of the Task.  If a display name is not set by the derived class, this defaults to the internal name.

=head2 get_summary / set_summary

Accessors for the summary of the Task.  If a summary is not set by the derived class, this defaults to the internal name.

=head2 add_dependencies

This method takes a list of internal names of Tasks that the derived Task depends on.

=head2 get_dependencies

This method returns a reference to an array that contains the list of internal names of the Tasks this Task depends on.

=head2 enable_only_perform_once

This method sets the flag that causes the Task to only ever be run once.  If the flag is set, and the history file indicates that the Task has been performed in the past, it will not be performed again.

=head2 disable_only_perform_once

This method unsets the flag that causes the Task to only ever be run once.  Only provided for completeness.

=head2 only_perform_once

This method returns true if the Task should only be run once, false otherwise.  By default, this flag is not set.

=head2 create_history_msg

This method creates a history message for inclusion in history file generated by taskrun.

=head2 dnsonly

Takes no arguments and returns true of the installation is of the dnsonly variety, false otherwise.


=head1 INTERFACE

Stubs are provided for the following methods.  Each is intended to be overridden by derived classes, but derived classes will still function if any or none are overridden.

=head2 perform

This method is the workhorse of any Task.  Anything the Task is supposed to accomplish should happen in this method.  If the Task succeeds in performing, this method should return true, false otherwise.  The default implementation of this method always returns true.

=head2 already_performed

If the implementer of derived classes wishes to do some kind of check to prevent the Task from running its perform method, this method may be overridden.  Returns true if the Task has already been performed, false otherwise.  The default implementation of this method always returns false.

=head2 undo

Override this method to provide a means to undo any changes to the system made by the perform method.  Return true if the undo operation was successful, false otherwise.  The default implementation of this method always returns false.

=head1 BUGS

While things that Tasks do are mostly encapsulated, it's still possible to shut down the taskrun system from inside (like by explicitly exiting).  Don't do that.  There are probably other ways to hose it, too.

=cut
