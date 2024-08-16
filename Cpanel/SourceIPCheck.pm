package Cpanel::SourceIPCheck;

# cpanel - Cpanel/SourceIPCheck.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Encoder::URI                          ();
use Cpanel::StringFunc::Count                     ();
use Cpanel::Reseller::Override                    ();
use Cpanel::Security::Policy::SourceIPCheck       ();
use Cpanel::Security::Policy::SourceIPCheck::Util ();
use Cpanel::SecurityPolicy::Utils                 ();
use Cpanel::Sort::Utils                           ();
use Cpanel::Logger                                ();
use Cpanel::Locale                                ();
use Cpanel::Imports;

my $logger = Cpanel::Logger->new();

sub SourceIPCheck_init { 1; }

sub api2_getaccount {
    my %OPTS    = @_;
    my $account = get_account( $OPTS{'account'} );
    $Cpanel::CPVAR{'account'} = $account;
    return [ { 'account' => $account } ];
}

sub api2_resetsecquestions {
    my %OPTS = @_;

    my $account = get_account( $OPTS{'account'} );
    my $success = 0;

    my $secpol_dir = Cpanel::SecurityPolicy::Utils::secpol_dir_from_homedir($Cpanel::homedir);
    $success = Cpanel::Security::Policy::SourceIPCheck::Util::resetsecquestions( $secpol_dir, $account );

    $Cpanel::context                   = 'sourceipcheck';
    $Cpanel::CPERROR{$Cpanel::context} = !$success || 0;
    $Cpanel::CPVAR{'status'}           = $success;
    return [ { 'status' => '' } ];
}

sub api2_savesecquestions {
    my %OPTS = @_;

    my $account = get_account( $OPTS{'account'} );
    $Cpanel::context = 'sourceipcheck';

    # Don't allow override login to change questions.
    if ( Cpanel::Reseller::Override::is_overriding() ) {    #TEMP_SESSION_SAFE
        $logger->warn("Attempting to save security questions for '$account' with Reseller or Root override is not allowed.");
        $Cpanel::CPERROR{$Cpanel::context} = $Cpanel::CPVAR{'questions'};
        $Cpanel::CPVAR{'status'} = 0;
        return [ { 'status' => 0 } ];
    }

    #    foreach my $q ( qw/q1ques q2ques q3ques q4ques/ ) {
    #        $OPTS{$q} = Cpanel::Encoder::Tiny::angle_bracket_encode( $OPTS{$q} );
    #    }
    my $secpol_dir     = Cpanel::SecurityPolicy::Utils::secpol_dir_from_homedir($Cpanel::homedir);
    my @questions      = map { [ $OPTS{"q${_}ques"}, $OPTS{"q${_}answer"} ] } ( 1 .. 4 );
    my $full_questions = Cpanel::Security::Policy::SourceIPCheck::Util::complete_questions( $secpol_dir, \@questions, $account );

    my $is_valid = Cpanel::Security::Policy::SourceIPCheck::Util::validatesecquestions( $full_questions, \%Cpanel::CPVAR );
    if ($is_valid) {
        eval { Cpanel::Security::Policy::SourceIPCheck::Util::savesecquestions( $secpol_dir, $full_questions, $account ); };
        if ($@) {
            $Cpanel::CPERROR{$Cpanel::context} = $Cpanel::CPVAR{'questions'};
            $Cpanel::CPVAR{'status'} = 0;
            return [ { 'status' => 0 } ];
        }
    }
    else {
        $Cpanel::CPERROR{$Cpanel::context} = $Cpanel::CPVAR{'questions'};
        $Cpanel::CPVAR{'status'} = 0;
        return [ { 'status' => 0 } ];
    }
    $Cpanel::CPVAR{'status'} = 1;
    return [ { 'status' => 1 } ];
}

sub get_account {
    my $requested_account = Cpanel::Encoder::URI::uri_decode_str(shift);

    if ( $Cpanel::appname eq 'webmail' ) {
        return ( $Cpanel::authuser || $ENV{'REMOTE_USER'} );
    }

    if ( $requested_account =~ /\@/ ) {

        my ( $user, $domain ) = split( /\@/, $requested_account, 2 );
        if ( grep( /^\Q$domain\E$/, @Cpanel::DOMAINS ) ) {
            return $requested_account;
        }
    }
    else {
        return ( $Cpanel::user || $ENV{'REMOTE_USER'} );
    }
}

sub api2_loadsecquestions {
    my %OPTS    = @_;
    my $account = get_account( $OPTS{'account'} );
    $Cpanel::context = 'sourceipcheck';
    my %questions;

    return [] if Cpanel::Reseller::Override::is_overriding();    #TEMP_SESSION_SAFE

    my @RSD;
    my $secpol_dir = Cpanel::SecurityPolicy::Utils::secpol_dir_from_homedir($Cpanel::homedir);
    eval {
        Cpanel::Security::Policy::SourceIPCheck::Util::loadsecquestions( $secpol_dir, \%questions, $account )
          if Cpanel::Security::Policy::SourceIPCheck::Util::has_security_questions( $secpol_dir, $account );
        1;
    } or do {
        $logger->warn( $@ || 'Error loading security questions' );
        return \@RSD;
    };

    for ( 1 .. Cpanel::Security::Policy::SourceIPCheck::Util::NUM_QUESTIONS ) {
        my $question_count = $_;
        my @QOPTS;
        if ( $Cpanel::FORM{ 'q' . $question_count } ) {
            $questions{ 'secq' . $question_count } = $Cpanel::FORM{ 'q' . $question_count };
        }

        for ( 1 .. Cpanel::Security::Policy::SourceIPCheck::Util::QUESTIONS_PER_BOX ) {
            my $question_number = $_ + ( ( $question_count - 1 ) * Cpanel::Security::Policy::SourceIPCheck::Util::QUESTIONS_PER_BOX );
            push @QOPTS, { 'questionnum' => $question_number, 'selectedtxt' => ( $questions{ 'secq' . $question_count } == $question_number ? 'selected' : '' ) };
        }

        push @RSD, { 'questionnum' => $question_count, 'question' => $questions{"secq$question_count"}, 'options' => \@QOPTS, 'answer' => $Cpanel::FORM{ 'q' . $question_count . 'answer' } };
    }
    return \@RSD;
}

sub api2_samplequestions {
    return scalar Cpanel::Security::Policy::SourceIPCheck::Util::samplequestions();
}

sub api2_addip {
    my %OPTS = @_;

    my $ip = $OPTS{'ip'};
    for ( 2 .. 4 ) {
        if ( defined $OPTS{ 'ip' . $_ } && $OPTS{ 'ip' . $_ } ne '' ) { $ip .= '.' . $OPTS{ 'ip' . $_ }; }
    }
    $ip =~ s/\*.*//g;

    if ( Cpanel::StringFunc::Count::countchar( $ip, '.' ) < 3 && $ip !~ /\.$/ ) {
        $ip .= '.';
    }

    $Cpanel::context = 'sourceipcheck';
    unless ( $ip =~ m/^(\d+\.){1,3}$/ or $ip =~ m/^\d+(.\d+){3}$/ ) {

        # Doesn't look like an IP or prefix for an IP.
        $Cpanel::CPVAR{'status'} = 0;
        return [ { status => 0, ip => $ip, error => locale->maketext( 'The supplied address “[_1]” is not a valid IP address.', $ip ) } ];
    }

    my $op         = $OPTS{'op'} || 'ADDIP';
    my $account    = get_account( $OPTS{'account'} );
    my $secpol_dir = Cpanel::SecurityPolicy::Utils::secpol_dir_from_homedir($Cpanel::homedir);
    my $success;
    if ( $op eq 'REMOVEIP' ) {
        $success = Cpanel::Security::Policy::SourceIPCheck::Util::deauthorize_ip( $secpol_dir, $account, $ip );
    }
    else {
        $success = Cpanel::Security::Policy::SourceIPCheck::Util::authorize_ip( $secpol_dir, $account, $ip );
    }

    my %output = ( ip => $ip );
    $output{status} = $Cpanel::CPVAR{'status'}           = $success ? 1 : 0;
    $output{error}  = $Cpanel::CPERROR{$Cpanel::context} = locale->maketext('Unable to update the IP list.') if !$success;

    return [ \%output ];
}

sub api2_delip {
    api2_addip( @_, 'op' => 'REMOVEIP' );
}

sub api2_listips {
    my %OPTS    = @_;
    my $account = get_account( $OPTS{'account'} );
    $Cpanel::context = 'sourceipcheck';
    my $sec_policy_dir = Cpanel::SecurityPolicy::Utils::secpol_dir_from_homedir($Cpanel::homedir);
    my $iplist_ref     = Cpanel::Security::Policy::SourceIPCheck::fetch_ip_list( $sec_policy_dir, $account );
    if ( !$iplist_ref ) { return []; }

    my @RSD;
    foreach my $ip ( Cpanel::Sort::Utils::sort_ipv4_list( [ keys %{$iplist_ref} ] ) ) {
        push @RSD, { 'ip' => $ip };
    }
    return \@RSD;
}

my $allow_demo = { allow_demo => 1 };
my $deny_demo  = {};

our %API = (
    listips           => $allow_demo,
    delip             => $deny_demo,
    addip             => $deny_demo,
    getaccount        => $allow_demo,
    resetsecquestions => $deny_demo,
    savesecquestions  => {
        modify      => 'none',
        xss_checked => 1,
    },
    loadsecquestions => $allow_demo,
    samplequestions  => $allow_demo,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
