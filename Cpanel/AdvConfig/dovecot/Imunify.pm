package Cpanel::AdvConfig::dovecot::Imunify;

# cpanel - Cpanel/AdvConfig/dovecot/Imunify.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::JSON            ();
use Cpanel::SafeRun::Object ();
use Cpanel::Debug           ();
use Cpanel::FindBin         ();

=encoding utf-8

=head1 NAME

Cpanel::AdvConfig::dovecot::Imunify

=head1 DESCRIPTION

This module is intended to manage the dovecot local template for the Imunify360 PAM extension.

More information on this feature can be found here:
https://blog.imunify360.com/preventing-brute-force-mail-attacks-with-new-pam-module-extension

=head1 METHODS

=head2 new()

Constructor.

=head3 Attributes

=over

=item * bin -- The imunify360-agent binary.

=back

=cut

sub new ( $pkg, $args = undef ) {

    my $self = {};

    $self->{'bin'} = Cpanel::FindBin::findbin('imunify360-agent');

    bless $self, $pkg;
    return $self;
}

=head2 get_imunify_config()

This method obtains the current running imunify360 config by invoking the imunify360 agent binary.

It returns the configuration as a hash ref.

=cut

sub get_imunify_config ($self) {
    my $rawjson = $self->_run_agent( [ 'config', 'show', '--json' ] );
    my $conf    = eval { Cpanel::JSON::Load($rawjson) };
    if ($@) {
        Cpanel::Debug::log_info("JSON parse error: $@");
        return;
    }
    return $conf;
}

=head2 needs_update()

This method determines if we need to update the local dovecot template. The imunify360 agent binary must
exist and the dovecot extension must be enabled.

Returns true if the template needs to be updated.

=cut

sub needs_update ($self) {

    # If there is no binary, there is nothing to do.
    return if !$self->{'bin'};

    # Check if the PAM extension is enabled.
    return if !$self->has_dovecot_extension();

    return 1;
}

=head2 has_dovecot_extension()

Checks to see if imunify360 has the dovecot PAM extension enabled.

It returns true if it is enabled.

=cut

sub has_dovecot_extension ($self) {
    my $conf = $self->get_imunify_config() // return;
    return unless $conf->{'items'}{'PAM'}{'exim_dovecot_protection'};
    return 1;
}

=head2 disable_extension()

Toggles PAM extension off.

Returns agent STDOUT if successful, or undef otherwise.

=cut

sub disable_extension ($self) {
    return $self->_set_extension(0);
}

=head2 enable_extension()

Toggles PAM extension on.

Returns agent STDOUT if successful, or undef otherwise.

=cut

sub enable_extension ($self) {
    return $self->_set_extension(1);
}

=head2 _set_extension($status)

Toggles PAM extension on or off depending on provided $status value.

Returns agent STDOUT if successful, or undef otherwise.

=cut

sub _set_extension ( $self, $status ) {
    my $bool = $status ? 'true' : 'false';
    return $self->_run_agent( [ 'config', 'update', qq<{"PAM": {"exim_dovecot_protection": $bool}}> ] );
}

=head2 refresh_local_template()

This forces Imunify360 to rebuild their local template based on the cPanel supplied template.

It returns true if it was completed, or undef if either PAM toggling fails or local dovecot template doesn't regenerate within 10 seconds.

=cut

sub refresh_local_template ($self) {
    return unless $self->disable_extension();
    return unless $self->enable_extension();

    # Returns undef on timeout, or 1 on success.
    my $ret = eval {
        require Cpanel::Alarm;
        require Cpanel::AdvConfig::dovecot;

        my $timeout = Cpanel::Alarm->new( 10, sub { die "Timed out while waiting for $self->{'bin'} to regenerate local dovecot template.\n"; } );
        sleep(1) until Cpanel::AdvConfig::dovecot::has_local_template();
    };

    Cpanel::Debug::log_info($@) if $@;
    return $ret;
}

=head2 _run_agent(\@args)

Runs imunify360-agent with the provided arrayref of args

Returns STDOUT if successful, or logs and returns undef on error.

=cut

sub _run_agent ( $self, $args ) {

    my $run;
    eval {
        $run = Cpanel::SafeRun::Object->new_or_die(
            'program' => $self->{'bin'},
            'args'    => $args,
        );
    };
    if ( my $err = $@ ) {
        Cpanel::Debug::log_info("Failed to run $self->{bin}: $err");
        return;
    }

    if ( $run->CHILD_ERROR() ) {
        my $out = $run->stdout() . $run->stderr();
        Cpanel::Debug::log_info("imunify360-agent: $out");
        return;
    }

    return $run->stdout();
}

1;
