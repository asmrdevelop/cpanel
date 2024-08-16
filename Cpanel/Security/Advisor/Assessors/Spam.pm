package Cpanel::Security::Advisor::Assessors::Spam;

# cpanel - Cpanel/Security/Advisor/Assessors/Spam.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::LoadFile     ();
use Whostmgr::Imunify360 ();

use base 'Cpanel::Security::Advisor::Assessors';

sub generate_advice {
    my ($self) = @_;
    $self->_check_for_nobody_tracking();

    return 1;
}

sub _check_for_nobody_tracking {
    my ($self) = @_;

    my $security_advisor_obj = $self->{'security_advisor_obj'};

    if ( $security_advisor_obj->{'cpconf'}->{'nobodyspam'} ) {
        $security_advisor_obj->add_advice(
            {
                'key'  => 'Spam_user_nobody_can_not_permitted_to_send_email',
                'type' => $Cpanel::Security::Advisor::ADVISE_GOOD,
                'text' => $self->_lh->maketext('The pseudo-user “nobody” is not permitted to send email.'),
            }
        );
    }
    else {
        $security_advisor_obj->add_advice(
            {
                'key'        => 'Spam_user_nobody_can_send_email',
                'type'       => $Cpanel::Security::Advisor::ADVISE_BAD,
                'text'       => $self->_lh->maketext('The pseudo-user “nobody” is permitted to send email.'),
                'suggestion' => $self->_lh->maketext(
                    'Enable ‘Prevent “nobody” from sending mail’ in the “[output,url,_1,Tweak Settings,_2,_3]” area',
                    $self->base_path('scripts2/tweaksettings?find=nobodyspam'),
                    'target',
                    '_blank'
                ),
            }
        );
    }

    if ( -e '/var/cpanel/smtpgidonlytweak' ) {
        $security_advisor_obj->add_advice(
            {
                'key'  => 'Spam_outbound_smtp_restricted',
                'type' => $Cpanel::Security::Advisor::ADVISE_GOOD,
                'text' => $self->_lh->maketext('Outbound SMTP connections are restricted.'),
            }
        );

    }
    elsif ( _csf_has_option( 'SMTP_BLOCK', '1' ) ) {
        $security_advisor_obj->add_advice(
            {
                'key'  => 'Spam_smtp_block_enabled',
                'type' => $Cpanel::Security::Advisor::ADVISE_GOOD,
                'text' => $self->_lh->maketext('CSF has SMTP_BLOCK enabled.'),
            }
        );
    }
    elsif (
        do {
            my $imunify360 = Whostmgr::Imunify360->new();
            $imunify360->is_running && $imunify360->check_config( sub { shift()->{'items'}{'SMTP_BLOCKING'}{'enable'} } );
        }
    ) {

        # It's also possible for SMTP blocking to be enabled in Imunify360 and remain ineffective because someone
        # has, for example, removed port 25 from the list; but we can assume that as long as the setting is enabled
        # (default is disabled), the server administrator has taken the time to configure it.
        $security_advisor_obj->add_advice(
            {
                'key'  => 'Spam_smtp_blocking_enabled_imunify360',
                'type' => $Cpanel::Security::Advisor::ADVISE_GOOD,
                'text' => $self->_lh->maketext('[asis,Imunify360] has [asis,SMTP_BLOCKING] enabled.'),
            }
        );
    }
    else {
        $security_advisor_obj->add_advice(
            {
                'key'        => 'Spam_smtp_unrestricted',
                'type'       => $Cpanel::Security::Advisor::ADVISE_BAD,
                'text'       => $self->_lh->maketext('Outbound SMTP connections are unrestricted.'),
                'suggestion' => $self->_lh->maketext(
                    'Enable SMTP Restrictions in the “[output,url,_1,SMTP Restrictions,_2,_3]” area',
                    $self->base_path('scripts2/smtpmailgidonly'),
                    'target',
                    '_blank'
                ),

            }
        );
    }

    if ( -e '/var/cpanel/config/email/query_apache_for_nobody_senders' ) {
        $security_advisor_obj->add_advice(
            {
                'key'  => 'Spam_apache_queried_for_sender',
                'type' => $Cpanel::Security::Advisor::ADVISE_GOOD,
                'text' => $self->_lh->maketext('Apache is being queried to determine the actual sender when mail originates from the “nobody” pseudo-user.'),
            }
        );
    }
    else {
        $security_advisor_obj->add_advice(
            {
                'key'        => 'Spam_apache_not_queried_for_sender',
                'type'       => $Cpanel::Security::Advisor::ADVISE_BAD,
                'text'       => $self->_lh->maketext('Apache is not being queried to determine the actual sender when mail originates from the “nobody” pseudo-user.'),
                'suggestion' => $self->_lh->maketext(
                    'Enable “Query Apache server status to determine the sender of email sent from processes running as nobody” in the “[output,url,_1,Exim Configuration Manager,_2,_3]” area’s “Basic Editor”',
                    $self->base_path('scripts2/displayeximconfforedit'),
                    'target',
                    '_blank'
                ),
            }
        );

    }

    return 1;
}

sub _csf_has_option {
    my ( $option, $value ) = @_;
    if ( -e '/etc/csf/csf.conf' ) {
        my $csf_conf = Cpanel::LoadFile::loadfile('/etc/csf/csf.conf');
        return 1 if $csf_conf =~ m/\n[ \t]*\Q$option\E[ \t]*=[ \t]*['"]\Q$value\E/s;
    }
    return 0;
}

1;
