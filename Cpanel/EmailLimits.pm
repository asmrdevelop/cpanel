package Cpanel::EmailLimits;

# cpanel - Cpanel/EmailLimits.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Config::LoadCpConf     ();
use Cpanel::LoadFile               ();
use Cpanel::Email::DeferThreshold  ();

my $EMAIL_DEFER_THRESHOLD;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = bless {}, $class;

    $EMAIL_DEFER_THRESHOLD ||= Cpanel::Email::DeferThreshold::defer_threshold();
    my %OPTS          = @_;
    my $maxemail_file = $OPTS{'maxemails_file'} || '/var/cpanel/maxemailsperhour';

    $self->{'cpconf'}                               = $OPTS{'cpconf'} || Cpanel::Config::LoadCpConf::loadcpconf();
    $self->{'max_emails_per_hour'}                  = int( Cpanel::LoadFile::loadfile($maxemail_file)                         || 0 );
    $self->{'max_defer_fail_percentage'}            = int( $self->{'cpconf'}->{'email_send_limits_max_defer_fail_percentage'} || 0 );
    $self->{'min_defer_fail_to_trigger_protection'} = $EMAIL_DEFER_THRESHOLD;
    $self->{'email_send_limit_default_key'}         = join( ',', $self->{'max_emails_per_hour'}, $self->{'max_defer_fail_percentage'}, $EMAIL_DEFER_THRESHOLD );

    $self;
}

sub get_email_send_limit_key {
    my ( $self, $user, $domain, $cpuserfile ) = @_;
    $cpuserfile            ||= Cpanel::Config::LoadCpUserFile::load($user);
    $EMAIL_DEFER_THRESHOLD ||= Cpanel::Email::DeferThreshold::defer_threshold();

    if (   ( $cpuserfile->{ 'MAX_EMAIL_PER_HOUR-' . $domain } && $cpuserfile->{ 'MAX_EMAIL_PER_HOUR-' . $domain } ne 'default' )
        || ( $cpuserfile->{'MAX_EMAIL_PER_HOUR'}                     && $cpuserfile->{'MAX_EMAIL_PER_HOUR'} ne 'default' )
        || ( $cpuserfile->{ 'MAX_DEFER_FAIL_PERCENTAGE-' . $domain } && $cpuserfile->{ 'MAX_DEFER_FAIL_PERCENTAGE-' . $domain } ne 'default' )
        || ( $cpuserfile->{'MAX_DEFER_FAIL_PERCENTAGE'}              && $cpuserfile->{'MAX_DEFER_FAIL_PERCENTAGE'} ne 'default' ) ) {
        my $MAX_EMAIL_PER_HOUR        = ( $cpuserfile->{ 'MAX_EMAIL_PER_HOUR-' . $domain }        && $cpuserfile->{ 'MAX_EMAIL_PER_HOUR-' . $domain } ne 'default' )        ? $cpuserfile->{ 'MAX_EMAIL_PER_HOUR-' . $domain }        : ( ( $cpuserfile->{'MAX_EMAIL_PER_HOUR'}        && $cpuserfile->{'MAX_EMAIL_PER_HOUR'} ne 'default' )        ? $cpuserfile->{'MAX_EMAIL_PER_HOUR'}        : '' );
        my $MAX_DEFER_FAIL_PERCENTAGE = ( $cpuserfile->{ 'MAX_DEFER_FAIL_PERCENTAGE-' . $domain } && $cpuserfile->{ 'MAX_DEFER_FAIL_PERCENTAGE-' . $domain } ne 'default' ) ? $cpuserfile->{ 'MAX_DEFER_FAIL_PERCENTAGE-' . $domain } : ( ( $cpuserfile->{'MAX_DEFER_FAIL_PERCENTAGE'} && $cpuserfile->{'MAX_DEFER_FAIL_PERCENTAGE'} ne 'default' ) ? $cpuserfile->{'MAX_DEFER_FAIL_PERCENTAGE'} : '' );
        return join( ',', $MAX_EMAIL_PER_HOUR, $MAX_DEFER_FAIL_PERCENTAGE, $EMAIL_DEFER_THRESHOLD );
    }
    return;

}

1;
