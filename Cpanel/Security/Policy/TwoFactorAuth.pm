package Cpanel::Security::Policy::TwoFactorAuth;

# cpanel - Cpanel/Security/Policy/TwoFactorAuth.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Cpanel::SecurityPolicy::Base';
use Cpanel::Locale::Lazy 'lh';

sub new {
    my $class = shift;

    # Compiler does not necessarily properly load the base class.
    unless ( exists $INC{'Cpanel/SecurityPolicy/Base.pm'} ) {
        eval 'require Cpanel::SecurityPolicy::Base;';
    }
    return Cpanel::SecurityPolicy::Base->init( $class, 20 );

}

sub fails {
    my ( $self, $sec_ctxt ) = @_;

    # If we already verified the tfa_token as part of the
    # authentication process, then we don't need to re-verify 2FA.
    return 0 if $sec_ctxt->{'tfa_verified'};

    my ( $user, $homedir );
    if ( $sec_ctxt->{'is_possessed'} ) {
        $user    = $sec_ctxt->{'possessor'};
        $homedir = $sec_ctxt->{'possessor_homedir'};
    }
    elsif ( defined $sec_ctxt->{'domain'} && defined $sec_ctxt->{'virtualuser'} ) {

        # webmail section
        $user    = $sec_ctxt->{'user'};
        $homedir = $sec_ctxt->{'homedir'};
    }
    else {
        $user    = $sec_ctxt->{'webmailowner'} // $sec_ctxt->{'user'};
        $homedir = $sec_ctxt->{'homedir'};
    }
    $user = $ENV{'TEAM_USER'} ? "$ENV{'TEAM_USER'}\@$ENV{'TEAM_OWNER'}" : $user;

    if ( tfa_enabled( $user, $sec_ctxt->{'appname'} ) ) {
        return 1;
    }

    return 0;
}

sub description {
    return lh()->maketext('Two-Factor Authentication: [asis,Google Authenticator]');
}

sub tfa_enabled {
    my ( $user, $app_name ) = @_;

    # This needs to be able to read the userdata both when running as root,
    # and when running as the user.
    # Because the 'first' pass through the call runs as root, but
    # after the 'token' has been verified in the process() call,
    # the check is done once again, but only this time we are running with
    # reduced privileges.
    if ( $> == 0 ) {
        require Cpanel::Config::userdata::TwoFactorAuth::Secrets;
        my $userdata = Cpanel::Config::userdata::TwoFactorAuth::Secrets->new( { 'read_only' => 1 } );
        return ( $userdata->read_userdata()->{$user} ? 1 : 0 );
    }

    # TODO : handle for regular
    require Cpanel::AdminBin::Call;
    my $tfa_config = Cpanel::AdminBin::Call::call( 'Cpanel', 'twofactorauth', 'GET_USER_CONFIGURATION', $user, $app_name );
    return ( $tfa_config->{'is_enabled'} ? 1 : 0 );
}

1;
