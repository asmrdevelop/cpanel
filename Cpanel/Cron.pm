package Cpanel::Cron;

# cpanel - Cpanel/Cron.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::SafeRun::Simple    ();
use Cpanel::Encoder::Tiny      ();
use Cpanel::Debug              ();
use Cpanel::Validate::EmailRFC ();
use Cpanel::Hash               ();
use Cpanel::Locale             ();
use Cpanel::Cron::Utils        ();
use Cpanel::Security::Authz    ();
use Cpanel::JailSafe           ();
use IO::Handle                 ();
use Cpanel::PwCache            ();
use Cpanel::SafeRun::Object    ();

our $VERSION = '2.4';

my $maxentries = 32768;
my $locale;

sub _install_crontab {
    my $crontab_arrayref = shift;

    #case 64400, prevent new lines from being added inside an entry
    if ( grep { $_ =~ m/[\r\f\n]/ } @$crontab_arrayref ) {
        $locale ||= Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext("New lines are not permitted in crontab entries.");
        return ( 0, $Cpanel::CPERROR{$Cpanel::context} );
    }

    my $crontab_text = join( qq{\n}, @{$crontab_arrayref} ) . qq{\n};

    Cpanel::Cron::Utils::enforce_crontab_shell( \$crontab_text, _get_cron_shell() );

    # TODO: write function to validate crontab and return a better error then the one the crontab binary returns
    my $run = Cpanel::SafeRun::Object->new(
        'program' => Cpanel::JailSafe::get_system_binary('crontab'),
        'stdin'   => $crontab_text,
        'args'    => [q{-}],
        'timeout' => '20',
    );

    if ( !$run || $run->timed_out() ) {
        $Cpanel::CPERROR{$Cpanel::context} = 'crontab failed to finish installing the new crontab and was terminated';
        return ( 0, $Cpanel::CPERROR{$Cpanel::context} );
    }
    elsif ( $run->stderr() ) {
        $Cpanel::CPERROR{$Cpanel::context} = $run->stderr();
        return ( 0, $Cpanel::CPERROR{$Cpanel::context} );
    }
    elsif ( $run->error_code() ) {

        # ie incorrect permissions, missing binary, internal failure of crontab, etc #
        $Cpanel::CPERROR{$Cpanel::context} = "crontab failed to install the new crontab (no reason provided), exit code was " . $run->error_code();
        return ( 0, $Cpanel::CPERROR{$Cpanel::context} );
    }

    return ( 1, 'crontab installed' );
}

sub _install_serialized_crontab {
    my $serialized_crontab = shift;
    return _install_crontab( [ map { _de_serialize_line($_) } @$serialized_crontab ] );
}

sub _de_serialize_line {
    my $line = shift;
    if ( $line->{'type'} eq 'variable' ) {
        return $line->{'key'} . '="' . $line->{'value'} . '"';
    }
    elsif ( $line->{'type'} eq 'command' ) {
        return join( ' ', $line->{'minute'}, $line->{'hour'}, $line->{'day'}, $line->{'month'}, $line->{'weekday'}, $line->{'command'} );
    }
    else {
        return $line->{'text'};
    }

}

sub _fetch_cron {
    my @CRON;
    my $line          = 0;
    my $commandnumber = 0;
    my $cron_arrayref = _fetch_crontab_as_arrayref();
    my $hash;
    foreach my $txt ( @{$cron_arrayref} ) {
        chomp();
        ++$line;
        $hash = Cpanel::Hash::get_fastest_hash($txt);
        if ( $txt =~ /^#/ ) {
            push @CRON,
              {
                'line'    => $line,
                'type'    => 'comment',
                'text'    => $txt,
                'linekey' => $hash
              };
        }
        elsif ( $txt =~ /^([^\s\=]+)=\"?([^\"]*)\"?/ ) {
            push @CRON,
              {
                'line'    => $line,
                'type'    => 'variable',
                'key'     => $1,
                'value'   => $2,
                'linekey' => $hash
              };
        }
        else {
            my ( $minute, $hour, $day, $month, $weekday, $command ) = split( /\s+/, $txt, 6 );
            if ( defined $command ) {
                push @CRON,
                  {
                    'line'          => $line,
                    'type'          => 'command',
                    'minute'        => $minute,
                    'hour'          => $hour,
                    'day'           => $day,
                    'month'         => $month,
                    'weekday'       => $weekday,
                    'command'       => $command,
                    'commandnumber' => ++$commandnumber,
                    'linekey'       => $hash
                  };
            }
            else {
                push @CRON,
                  {
                    'line'    => $line,
                    'type'    => 'unknown',
                    'text'    => $txt,
                    'linekey' => $hash
                  };
            }
        }
    }
    return \@CRON;
}

sub _fetch_crontab_as_arrayref {
    local $ENV{'LC_ALL'} = 'C';
    my $line_count    = 0;
    my $comment_count = 0;
    return [
        grep { !/^no crontab for/ }
          grep {
            $line_count++;
            $comment_count++ if /^#/;
            ( $line_count > 3 || $line_count != $comment_count ) ? 1 : 0;
          } split( /\n/, Cpanel::SafeRun::Simple::saferun( Cpanel::JailSafe::get_system_binary('crontab'), '-l' ) )
    ];

}

sub _list_cron {
    my @CRON_ENTRIES;
    my $parsed_crontab_ref = _fetch_cron();
    foreach my $lineref (@$parsed_crontab_ref) {
        if ( $lineref->{'type'} eq 'command' ) {
            push @CRON_ENTRIES, [ $lineref->{'minute'}, $lineref->{'hour'}, $lineref->{'day'}, $lineref->{'month'}, $lineref->{'weekday'}, $lineref->{'command'}, $lineref->{'linekey'} ];
        }
    }
    return \@CRON_ENTRIES;
}

sub list_cron {

    if ( !main::hasfeature("cron") ) { return (); }
    return map { $_->[5] = Cpanel::Encoder::Tiny::safe_html_encode_str( $_->[5] ); $_ } @{ _list_cron() };
}

sub _set_email {
    my ($email) = @_;

    if ( $email && $email ne $Cpanel::user && !Cpanel::Validate::EmailRFC::is_valid($email) ) {
        return ( 0, 'Invalid Email Address' );
    }

    if ( !$email ) {
        $email = '';
    }

    my $set_mail_to = 0;
    my $cronref     = _fetch_cron();
    for my $i ( 0 .. $#$cronref ) {
        if ( $cronref->[$i]{'type'} eq 'variable' && $cronref->[$i]{'key'} eq 'MAILTO' ) {
            if ($set_mail_to) {
                $cronref->[$i] = undef;    #remove dupes
            }
            else {
                $cronref->[$i]{'value'} = $email;
                $set_mail_to = 1;
            }
        }
    }

    @$cronref = grep { ref $_ } @$cronref;    #remove non refs

    if ( !$set_mail_to ) {
        unshift @$cronref,
          {
            'line'  => 1,
            'type'  => 'variable',
            'key'   => 'MAILTO',
            'value' => $email,
          };
        $cronref->[$#$cronref]{'linekey'} = Cpanel::Hash::get_fastest_hash( _de_serialize_line( $cronref->[$#$cronref] ) );
        for my $i ( 1 .. $#$cronref ) {
            $cronref->[$i]{'line'}++;
        }
    }

    return _install_serialized_crontab($cronref);
}

sub _get_email {
    my $mailto = $Cpanel::user;
    foreach my $line ( @{ _fetch_cron() } ) {
        if ( $line->{'type'} eq 'variable' && $line->{'key'} eq 'MAILTO' ) {
            $mailto = $line->{'value'};
        }
    }
    return $mailto;
}

sub list_cronmailto {
    if ( !main::hasfeature('cron') ) { return (); }
    my $mailto = _get_email();
    return Cpanel::Encoder::Tiny::safe_html_encode_str($mailto);
}

sub edit_cron {
    if ( !main::hasfeature('cron') ) { return (); }
    local $Cpanel::IxHash::Modify = 'none';
    my $numentries = $maxentries;
    if ( $Cpanel::FORM{'entcount'} ) {
        $numentries = ( int $Cpanel::FORM{'entcount'} ) + 1;
    }
    if ( $numentries > $maxentries ) {
        $numentries = $maxentries;
    }
    if ( $Cpanel::CPDATA{'DEMO'} eq "1" ) {
        print "Sorry Cron Jobs cannot be editted in this demo\n";
        return "";
    }

    my $cronshell = get_cron_shell();
    my @CRONTAB;
    push @CRONTAB, 'MAILTO="' . $Cpanel::FORM{'mailto'} . '"';
    push @CRONTAB, $cronshell . "\n" if $cronshell;
    for my $i ( 0 .. $numentries ) {
        if (   ( $Cpanel::FORM{ $i . '-minute' } =~ /^\d+|\*/ )
            && ( $Cpanel::FORM{ $i . '-hour' }    =~ /^\d+|\*/ )
            && ( $Cpanel::FORM{ $i . '-day' }     =~ /^\d+|\*/ )
            && ( $Cpanel::FORM{ $i . '-month' }   =~ /^\d+|\*/ )
            && ( $Cpanel::FORM{ $i . '-weekday' } =~ /^\d+|\*/ )
            && ( $Cpanel::FORM{ $i . '-command' } ) ) {
            push @CRONTAB, $Cpanel::FORM{ $i . '-minute' } . ' ' . $Cpanel::FORM{ $i . '-hour' } . ' ' . $Cpanel::FORM{ $i . '-day' } . ' ' . $Cpanel::FORM{ $i . '-month' } . ' ' . $Cpanel::FORM{ $i . '-weekday' } . ' ' . $Cpanel::FORM{ $i . '-command' };
        }
    }
    my ( $status, $statusmsg ) = _install_crontab( \@CRONTAB );
    if ( !$status ) {
        print $statusmsg;
    }
}

sub edit_cronsimple {
    if ( !main::hasfeature("cron") ) { return (); }
    local $Cpanel::IxHash::Modify = 'none';

    my $numentries = $maxentries;
    if ( $Cpanel::FORM{'entcount'} ) {
        $numentries = ( int $Cpanel::FORM{'entcount'} ) + 1;
    }
    if ( $numentries > $maxentries ) {
        $numentries = $maxentries;
    }

    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        print "Sorry, cron jobs cannot be editted in this demo.\n";
        return '';
    }
    my $cronshell = get_cron_shell();
    my @CRONTAB;
    push @CRONTAB, 'MAILTO="' . $Cpanel::FORM{'mailto'} . '"';
    push @CRONTAB, $cronshell . "\n" if $cronshell;

    for my $i ( 0 .. $numentries ) {
        my $cl;
        foreach (qw(minute hour day month weekday)) {
            $cl .= $Cpanel::FORM{ $_ . $i } eq '' ? '*' : $Cpanel::FORM{ $_ . $i };

            my $t = 0;
            while ( $Cpanel::FORM{ $_ . $i . '-' . $t } ne '' ) {
                $cl .= ',' . $Cpanel::FORM{ $_ . $i . '-' . $t };
                $t++;
            }
            $cl .= ' ';
        }
        my $key = 'command_htmlsafe' . $i;
        if ( $Cpanel::FORM{ 'command_htmlsafe' . $i } eq '' && $Cpanel::FORM{ 'command' . $i } ne '' ) {
            $key = 'command' . $i;
        }

        $cl .= $Cpanel::FORM{$key};

        if ( $Cpanel::FORM{$key} ne '' ) {
            push @CRONTAB, $cl;
        }
    }
    my ( $status, $statusmsg ) = _install_crontab( \@CRONTAB );
    if ( !$status ) {
        print $statusmsg;
    }
}

sub _get_cron_shell {
    return Cpanel::Cron::Utils::get_user_cron_shell( $Cpanel::user || Cpanel::PwCache::getusername() );
}

sub get_cron_shell {
    Cpanel::Security::Authz::verify_user_has_feature( $Cpanel::user, 'cron' );

    my $cron_shell = _get_cron_shell();

    Cpanel::Cron::Utils::validate_cron_shell_or_die($cron_shell);

    if ($cron_shell) { return 'SHELL=' . $cron_shell; }

    return '';
}

sub api2_fetchcron {
    return _fetch_cron();
}

sub api2_listcron {
    my %OPTS = @_;

    my @RCTAB;
    my $count = 0;

    foreach my $tab ( @{ _list_cron() } ) {
        push(
            @RCTAB,
            {
                'count'            => ++$count,
                'minute'           => $tab->[0],
                'hour'             => $tab->[1],
                'day'              => $tab->[2],
                'month'            => $tab->[3],
                'weekday'          => $tab->[4],
                'command'          => $tab->[5],
                'command_htmlsafe' => Cpanel::Encoder::Tiny::safe_html_encode_str( $tab->[5] ),
                'linekey'          => $tab->[6],
            }
        );
    }

    if ( !$OPTS{'omit_extra_record'} ) {

        # This is used in the simple crontab editor in cPanel
        # to designate the id of a new record, and has been in
        # place for a very long time.
        push @RCTAB, { 'count' => ++$count };
    }

    return \@RCTAB;
}

sub _remove_cron_commands_by_key {
    my ( $key, $keyvalue ) = @_;

    my @old_crontab = @{ _fetch_cron() };
    my @new_crontab = grep { $_->{$key} ne $keyvalue } @old_crontab;

    return _install_serialized_crontab( \@new_crontab ) if $#old_crontab > $#new_crontab;
    return ( 0, "Cron job not found in the crontab." );
}

sub rem_cron {
    if ( !main::hasfeature("cron") ) { return (); }

    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        print "Sorry, cron jobs cannot be removed in this demo.\n";
        return '';
    }

    my $commandnumber = shift;
    return _remove_cron_commands_by_key( 'commandnumber', $commandnumber );
}

sub api2_remove_line {
    my %OPTS = @_;

    my ( $status, $statusmsg );

    if ( exists $OPTS{'linekey'} && $OPTS{'linekey'} ) {
        ( $status, $statusmsg ) = _remove_cron_commands_by_key( 'linekey', $OPTS{'linekey'} );
    }
    elsif ( ( exists $OPTS{'line'} && $OPTS{'line'} ) || ( exists $OPTS{'commandnumber'} && $OPTS{'commandnumber'} ) ) {
        ( $status, $statusmsg ) = _remove_cron_commands_by_key( 'commandnumber', ( $OPTS{'line'} || $OPTS{'commandnumber'} ) );
    }
    else {
        ( $status, $statusmsg ) = ( 0, 'You must specify line, commandnumber, or linekey' );
    }

    return [ { 'status' => $status, 'statusmsg' => $statusmsg } ];
}

sub _add_cron_command {
    my $command_ref = shift;
    $command_ref->{'linekey'} = Cpanel::Hash::get_fastest_hash( _de_serialize_line($command_ref) );
    my $cronref = _fetch_cron();

    #Jira ticket CPANEL-37510
    #If and only if there is an empty crontab then it will add a MAILTO user. If the crontab is already
    #in use, then we probably do not want to change the existing behavior of cron or how it reports its
    #successes and failures to the user. Only if this is a new user, or the user completely clears out
    #their crontab and then adds new lines will it add the MAILTO="" to the crontab,
    #because crontab will again be blank.
    if ( scalar @$cronref == 0 ) {
        push @$cronref,
          {
            'line'  => 1,
            'type'  => 'variable',
            'key'   => 'MAILTO',
            'value' => '',
          };
    }
    return ( 0, "This cron job already exists." ) if ( grep { $_->{'linekey'} eq $command_ref->{'linekey'} } @$cronref );
    push @$cronref, $command_ref;
    return _install_serialized_crontab($cronref);
}

sub api2_add_line {
    my %OPTS = @_;

    my $command_ref = {
        'type'    => 'command',
        'minute'  => $OPTS{'minute'},
        'hour'    => $OPTS{'hour'},
        'day'     => $OPTS{'day'},
        'month'   => $OPTS{'month'},
        'weekday' => $OPTS{'weekday'},
        'command' => $OPTS{'command'},
    };

    my ( $status, $statusmsg ) = _add_cron_command($command_ref);
    $statusmsg ||= '';

    return [ { 'status' => $status, 'statusmsg' => $statusmsg, 'linekey' => Cpanel::Hash::get_fastest_hash( _de_serialize_line($command_ref) ) } ];
}

sub _edit_cron_command {
    my ( $old_command_ref, $command_ref ) = @_;
    my @current_crontab = @{ _fetch_cron() };

    $command_ref->{'linekey'}       = Cpanel::Hash::get_fastest_hash( _de_serialize_line($command_ref) );
    $command_ref->{'commandnumber'} = $old_command_ref->{'commandnumber'};

    my $key = ( ( exists $old_command_ref->{'linekey'} && defined $old_command_ref->{'linekey'} ) ? 'linekey' : 'commandnumber' );

    return ( 0, "This cron job already exists." ) if ( grep { $_->{'linekey'} eq $command_ref->{'linekey'} } @current_crontab );

    return ( 0, "Could not find $key=" . $old_command_ref->{$key} ) if !grep { $_->{$key} eq $old_command_ref->{$key} } @current_crontab;

    return _install_serialized_crontab( [ map { ( $_->{$key} eq $old_command_ref->{$key} ) ? $command_ref : $_ } @current_crontab ] );
}

sub api2_edit_line {
    my %OPTS = @_;

    my $command_ref = {
        'type'    => 'command',
        'minute'  => $OPTS{'minute'},
        'hour'    => $OPTS{'hour'},
        'day'     => $OPTS{'day'},
        'month'   => $OPTS{'month'},
        'weekday' => $OPTS{'weekday'},
        'command' => $OPTS{'command'},
    };
    my ( $status, $statusmsg ) = _edit_cron_command(
        {
            'linekey'       => $OPTS{'linekey'},
            'commandnumber' => ( $OPTS{'line'} || $OPTS{'commandnumber'} )
        },
        $command_ref
    );

    $statusmsg ||= '';
    return [ { 'status' => $status, 'statusmsg' => $statusmsg, 'linekey' => Cpanel::Hash::get_fastest_hash( _de_serialize_line($command_ref) ) } ];
}

sub crontab_perms {

    return if !main::hasfeature('cron');
    my $crontab_bin = Cpanel::JailSafe::get_system_binary('crontab');
    my $mode        = ( stat($crontab_bin) )[2];
    my $perms       = $mode & 07777;

    my $desired_perms = Cpanel::Cron::Utils::CORRECT_CRONTAB_BIN_PERMISSIONS();

    if ( $perms != $desired_perms ) {
        $locale ||= Cpanel::Locale->get_handle();
        my $display_perms         = sprintf '%04o', $perms;
        my $display_desired_perms = sprintf '%04o', $desired_perms;
        Cpanel::Debug::log_info("Permissions check for $crontab_bin failed. Not executable. Unable to use user cronjobs via cPanel.");
        return $locale->maketext( 'Permissions on “[_1]” are wrong ([_2]). Change the permissions to “[_3]”.', $crontab_bin, $display_perms, $display_desired_perms );
    }

    return '';
}

sub api2_get_email {
    return [ { 'email' => _get_email() } ];
}

sub api2_set_email {
    my %OPTS = @_;

    my ( $status, $statusmsg ) = _set_email( $OPTS{'email'} );
    $statusmsg ||= '';

    return [ { 'email' => $OPTS{'email'}, 'status' => $status, 'statusmsg' => $statusmsg } ];
}

my $cron_feature_deny_demo = {
    needs_feature => "cron",
    needs_role    => 'WebServer',
};

my $cron_feature_allow_demo = {
    %$cron_feature_deny_demo,
    allow_demo => 1,
};

our %API = (
    set_email   => $cron_feature_deny_demo,
    get_email   => $cron_feature_allow_demo,
    edit_line   => $cron_feature_deny_demo,
    add_line    => $cron_feature_deny_demo,
    listcron    => $cron_feature_allow_demo,
    fetchcron   => $cron_feature_allow_demo,
    remove_line => $cron_feature_deny_demo,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
