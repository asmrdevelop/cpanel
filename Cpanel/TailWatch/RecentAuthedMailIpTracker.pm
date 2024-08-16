package Cpanel::TailWatch::RecentAuthedMailIpTracker;

# cpanel - Cpanel/TailWatch/RecentAuthedMailIpTracker.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#############################################################
# no other use()s, require() only *and* only then in init() #
#############################################################

# /usr/local/cpanel already in @INC
# should work with these on but disabled in production for slight memory gain
# use strict;
# use warnings;
# use vars qw($VERSION);
## no critic qw(RequireUseStrict)
## no critic qw(RequireUseWarnings)

use Cpanel::TailWatch::Base ();    # Because we're explicitly calling into it.
use Cpanel::OS              ();
use base 'Cpanel::TailWatch::Base';

our $VERSION = 1.2;

our $CONFIG_FILE_PATH = '/etc/antirelayd.conf';    #For legacy reasons this is still called antirelayd.conf

#############################################################
# no other use()s, require() only *and* only then in init() #
#############################################################

#############################################################
# no other use()s, require() only *and* only then in init() #
#############################################################

sub init {

    # this is where modules should be require()'d
    # this method gets called if PKG->is_enabled()
    require Cpanel::IP::Parse;
    require Cpanel::FileUtils::Open;
    require Cpanel::IP::LocalCheck;
    require Cpanel::TailWatch;
    return 1;
}

sub internal_name { return 'recentauthedmailiptracker'; }

sub disable {
    my ( $tailwatch_obj, $my_ns ) = @_;

    # Notice the odd argument order due to
    # the history of the Cpanel::Tailwatch system
    Cpanel::TailWatch::Base::disable( $tailwatch_obj, $my_ns );

    # empty files it manages when enabled (case 43150)
    $my_ns->_write_etc_files( '', '', $tailwatch_obj );
    system '/usr/local/cpanel/scripts/update_exim_rejects';

    return 1;
}

sub new {
    my ( $my_ns, $tailwatch_obj ) = @_;
    my $self = bless { 'internal_store' => { 'host_list_stale' => 0, 'last_write_time' => 0 } }, $my_ns;

    $self->_load_demousers();
    $self->_load_demodomains();
    $self->_load_conf();
    $self->_load_alwaysrelay();
    $tailwatch_obj->{'global_share'}{'users'} = {};
    $tailwatch_obj->{'global_share'}{'hosts'} = {};

    my $maillog = Cpanel::OS::maillog_path();
    $maillog = $maillog . '.0' if !-f $maillog;
    $maillog = '/var/log/mail' if !-f $maillog;

    $tailwatch_obj->register_module( $self, __PACKAGE__, Cpanel::TailWatch::BACK30LINES(), [$maillog] );
    $tailwatch_obj->register_action_module( $self, __PACKAGE__ );

    $self->{'process_line_regex'}->{$maillog} = qr/(?:imapd|imapd-ssl|pop3d|pop3d-ssl|imap|dovecot)(\[\d+\])?:\s+.*login/ai;

    return $self;
}

sub process_line {
    my ( $self, $line, $tailwatch_obj, $logfile, $now_time ) = @_;

    return if !$line;

    my ( $srvlog, $data ) = split( /\: /, $line, 2 );
    return if ( !$srvlog || !$data );

    # Verify service
    if ( $srvlog =~ m/(\S+)$/ ) {
        my $server = $1;
        $server =~ s/\[[^\]]+\]//g;
        return if $server !~ m/(?:imapd|imapd-ssl|pop3d|pop3d-ssl|imap|dovecot)$/;
    }
    else {
        return;
    }

    return if ( $data =~ m/^login\s+failed/i );    # Prevent failed logins from being used

    $now_time ||= time;

    #dovecot
    if ( $data =~ m/^(?:imap|pop3)-login:\s+login:\s+user=\<([^\>]+)\>\,?\s+\S+\s+rip=([^\,\s]+)\,?\s+/i ) {
        my $user   = $1;
        my $ipdata = $2;
        $ipdata =~ s/,+$//;    # handle [::ffff:10.250.0.22],
        my ( $version, $ip, $port ) = Cpanel::IP::Parse::parse($ipdata);
        $self->_set_host( $tailwatch_obj, $ip, $now_time );
        $self->_set_host_user( $tailwatch_obj, $ip, $user, $now_time );
    }
    elsif ( $data =~ m/^login\s+[^\[]+\[(\d+\.\d+\.\d+\.\d+)/i ) {
        my $host = $1;
        $self->_set_host( $tailwatch_obj, $host, $now_time );
        if ( $data =~ m/realuser=(\S+)/ ) {
            $self->_set_host_user( $tailwatch_obj, $host, $1, $now_time );
        }
        elsif ( $data !~ m/^logout/i && $data =~ m/user=(\S+)/ ) {
            $self->_set_host_user( $tailwatch_obj, $host, $1, $now_time );
        }
    }
    elsif ( $data =~ m/^login\,?\s+user=(\S+)\,?[\s\t]+ip=(\S+)/i ) {
        my $ipdata = $2;
        my $user   = $1;
        $ipdata =~ s/,+$//;    # handle [::ffff:10.250.0.22],
        my ( $version, $ip, $port ) = Cpanel::IP::Parse::parse($ipdata);
        $self->_set_host( $tailwatch_obj, $ip, $now_time );
        $user =~ s/\,$//g;
        my $hostname = $tailwatch_obj->{'global_share'}{'data_cache'}{'hostname'};
        $user =~ s/\@(?:localhost|\Q$hostname\E)\,?$//gi;
        $self->_set_host_user( $tailwatch_obj, $ip, $user, $now_time );
    }
    elsif ( $data =~ m/^login\s+\S+\s+\S+\s+host=(\S+)/i ) {
        my $host = $1;
        $self->_set_host( $tailwatch_obj, $host, $now_time );
        if ( $data =~ m/realuser=(\S+)/ ) {
            my $user = $1;
            $self->_set_host_user( $tailwatch_obj, $host, $user, $now_time );
        }
        elsif ( $data !~ m/^logout/i && $data =~ m/user=(\S+)/ ) {
            my $user = $1;
            $self->_set_host_user( $tailwatch_obj, $host, $user, $now_time );
        }
    }
    elsif ( $data =~ m/^login\s+\S+\s+host=(\S+)/i ) {
        my $host = $1;
        $self->_set_host( $tailwatch_obj, $host, $now_time );
        if ( $data =~ m/realuser=(\S+)/ ) {
            my $user = $1;
            $self->_set_host_user( $tailwatch_obj, $host, $user, $now_time );
        }
        elsif ( $data !~ m/^logout/i && $data =~ m/user=(\S+)/ ) {
            my $user = $1;
            $self->_set_host_user( $tailwatch_obj, $host, $user, $now_time );
        }
    }
    elsif ( $data =~ m/^login\s+host=(\S+)\s+ip=(\S+)/i ) {
        my $host   = $1;
        my $ipdata = $2;
        $ipdata =~ s/,+$//;    # handle [::ffff:10.250.0.22],
        my ( $version, $ip, $port ) = Cpanel::IP::Parse::parse($ipdata);
        $self->_set_host( $tailwatch_obj, $host, $now_time );
        $self->_set_host( $tailwatch_obj, $ip,   $now_time );
        if ( $data =~ m/realuser=(\S+)/ ) {
            my $user = $1;
            $self->_set_host_user( $tailwatch_obj, $host, $user, $now_time );
            $self->_set_host_user( $tailwatch_obj, $ip,   $user, $now_time );
        }
        elsif ( $data !~ m/^logout/i && $data =~ m/user=(\S+)/ ) {
            my $user = $1;
            $self->_set_host_user( $tailwatch_obj, $host, $user, $now_time );
            $self->_set_host_user( $tailwatch_obj, $ip,   $user, $now_time );
        }
    }
    elsif ( $data =~ m/^login\s+host=(\S+)/i ) {
        my $host = $1;
        $self->_set_host( $tailwatch_obj, $host, $now_time );
        if ( $data =~ m/realuser=(\S+)/ ) {
            my $user = $1;
            $self->_set_host_user( $tailwatch_obj, $host, $user, $now_time );
        }
        elsif ( $data !~ m/^logout/i && $data =~ m/user=(\S+)/ ) {
            my $user = $1;
            $self->_set_host_user( $tailwatch_obj, $host, $user, $now_time );
        }
    }

    $self->_writehosts_if_needed( $tailwatch_obj, $now_time );
    return 1;
}

sub _writehosts_if_needed {
    my ( $self, $tailwatch_obj, $now_time ) = @_;
    if ( $self->{'internal_store'}{'host_list_stale'} || ( $self->{'internal_store'}{'last_write_time'} < ( $now_time - ( 60 * $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'expire_host_mins'} ) ) ) ) {
        $self->_writehosts( $tailwatch_obj, $now_time );

        return $self->_migrate_relayhosts_to_recent_authed_mail_ips();
    }
    return 1;
}

*run = \&_writehosts_if_needed;

sub _set_host {
    my ( $self, $tailwatch_obj, $host, $now_time ) = @_;

    return if Cpanel::IP::LocalCheck::ip_is_on_local_server($host);

    if ( !exists $tailwatch_obj->{'global_share'}{'hosts'}->{$host} ) {
        $self->{'internal_store'}{'host_list_stale'} = 1;
    }
    $tailwatch_obj->{'global_share'}{'hosts'}->{$host} = $now_time;
    return 1;
}

sub _set_host_user {
    my ( $self, $tailwatch_obj, $host, $user, $now_time ) = @_;

    return if Cpanel::IP::LocalCheck::ip_is_on_local_server($host);

    if ( !exists $tailwatch_obj->{'global_share'}{'users'}->{$host} || !exists $tailwatch_obj->{'global_share'}{'users'}->{$host}{$user} ) {
        $self->{'internal_store'}{'host_list_stale'} = 1;
    }
    $tailwatch_obj->{'global_share'}{'users'}->{$host}{$user} = $now_time;
    return 1;
}

## Driver specific helpers ##

sub _writehosts {
    my ( $self, $tailwatch_obj, $now ) = @_;

    $self->_check_conf();

    $self->{'internal_store'}{'last_write_time'} = $now;
    $self->{'internal_store'}{'host_list_stale'} = 0;

    my $exptime = ( $now - ( 60 * $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'expire_host_mins'} ) );

    $self->_check_demousers();
    $self->_check_demodomains();
    $self->_check_alwaysrelay();

    # REMOVE Expired, Demo, and loopback hosts
    foreach my $host ( sort keys %{ $tailwatch_obj->{'global_share'}{'hosts'} } ) {
        if ( $tailwatch_obj->{'global_share'}{'hosts'}->{$host} > $exptime && $host ) {
            if ( Cpanel::IP::LocalCheck::ip_is_on_local_server($host) ) {
                delete $tailwatch_obj->{'global_share'}{'users'}->{$host};
                delete $tailwatch_obj->{'global_share'}{'hosts'}->{$host};

            }
            my $demo           = 0;
            my $host_users_ref = $tailwatch_obj->{'global_share'}{'users'}->{$host};
            foreach my $user ( sort keys %{$host_users_ref} ) {
                $user =~ s/[\+\%\/\:]/\@/g;
                if ( $user =~ /\@/ ) {
                    my $domain = ( split( /\@/, $user ) )[1];
                    next if !$domain;

                    if ( exists $self->{'internal_store'}{'demodomains'}{$domain} ) {
                        $demo = 1;
                    }
                    else {
                        $demo = 0;    #never a demo
                        last;
                    }
                }
                elsif ( exists $self->{'internal_store'}{'demousers'}{$user} ) {
                    $demo = 1;
                }
                else {
                    $demo = 0;
                    last;
                }
            }
            if ($demo) {
                delete $tailwatch_obj->{'global_share'}{'users'}->{$host};
                delete $tailwatch_obj->{'global_share'}{'hosts'}->{$host};
            }
        }
        else {
            delete $tailwatch_obj->{'global_share'}{'hosts'}->{$host};
            delete $tailwatch_obj->{'global_share'}{'users'}->{$host};
        }
    }

    # Add alwaysrelay

    $tailwatch_obj->debug( "\n[alwaysrelay]=" . join( ",", keys %{ $self->{'internal_store'}{'alwaysrelay'} } ) . "\n" ) if $tailwatch_obj->{'debug'};

    foreach my $host ( keys %{ $self->{'internal_store'}{'alwaysrelay'} } ) {
        if ( !exists $tailwatch_obj->{'global_share'}{'hosts'}->{$host} ) {
            $tailwatch_obj->{'global_share'}{'hosts'}->{$host} = $now;
        }
        if ( !exists $tailwatch_obj->{'global_share'}{'users'}->{$host} || scalar keys %{ $tailwatch_obj->{'global_share'}{'users'}->{$host} } == 0 ) {
            if ( $self->{'internal_store'}{'alwaysrelay'}{$host} ) {
                my $alwaysrelayuser = $self->{'internal_store'}{'alwaysrelay'}{$host};
                $tailwatch_obj->{'global_share'}{'users'}->{$host}->{$alwaysrelayuser} = $now;
            }
            else {
                $tailwatch_obj->{'global_share'}{'users'}->{$host}->{'-alwaysrelay-'} = $now;
            }
        }
    }

    my $host_users_ref;
    my $relayhostusers_content = join(
        "\n",
        map {
            $host_users_ref = $tailwatch_obj->{'global_share'}{'users'}->{$_};
            ( $_ =~ m{:} ? qq{"$_"} : $_ ) . ": "
              . join(
                ', ', sort { $host_users_ref->{$b} <=> $host_users_ref->{$a} }
                  keys %{$host_users_ref}
              )
        } keys %{ $tailwatch_obj->{'global_share'}{'hosts'} }
    );
    $relayhostusers_content .= "\n" if length $relayhostusers_content;
    my $recent_authed_mail_ips_content = join( "\n", map { $_ =~ m{:} ? qq{"$_"} : $_ } keys %{ $tailwatch_obj->{'global_share'}{'hosts'} } );
    $recent_authed_mail_ips_content .= "\n" if length $recent_authed_mail_ips_content;

    $tailwatch_obj->debug("\n[$self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'recent_authed_mail_ips'}]\n$recent_authed_mail_ips_content\n[$self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'recent_authed_mail_ips_users'}]\n$relayhostusers_content\n") if $tailwatch_obj->{'debug'};

    return $self->_write_etc_files( $recent_authed_mail_ips_content, $relayhostusers_content, $tailwatch_obj );
}

sub _write_etc_files {
    my ( $self, $recent_authed_mail_ips_content, $relayhostusers_content, $tailwatch_obj ) = @_;

    # We previously used safefile here, however exim didn't observe the locks so there was as race condition
    # that meant the file could be empty during the looking.  We now build a .build file and rename it in place
    # in order to avoid the race condition since rename() will is synchronous.
    foreach my $file ( 'recent_authed_mail_ips', 'recent_authed_mail_ips_users' ) {

        if ( !$self->{'internal_store'}{'recentauthedmailiptracker_conf'}{$file} ) {
            die "_write_etc_files called before init and recentauthedmailiptracker_conf for $file is not defined";
        }

        if ( Cpanel::FileUtils::Open::sysopen_with_real_perms( my $recent_authed_mail_ips_fh, $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{$file} . '.build', 'O_WRONLY|O_CREAT', 0644 ) ) {
            print {$recent_authed_mail_ips_fh} ( $file eq 'recent_authed_mail_ips' ? $recent_authed_mail_ips_content : $relayhostusers_content );
            close($recent_authed_mail_ips_fh);
            if ( !rename( $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{$file} . '.build', $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{$file} ) ) {
                $tailwatch_obj->error("Could not rename $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{$file}.build  to $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{$file}: $!");
            }
        }
        else {
            $tailwatch_obj->error("Could not write to $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{$file}: $!");
        }
    }

    return if !-z $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'recent_authed_mail_ips'} || !-z $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'recent_authed_mail_ips_users'};
    return 1;
}

sub _check_demousers {
    my ($self) = @_;
    if ( !exists $self->{'internal_store'}{'demousers_cache_time'} ) {
        $self->{'internal_store'}{'demousers_cache_time'} = 0;
    }
    my $mtime = int( ( stat('/etc/demousers') )[9] );
    if ( ( $self->{'internal_store'}{'demousers_cache_time'} + 1800 ) < $mtime ) {
        $self->_load_demousers();
    }
    return 1;
}

sub _load_demousers {
    my ($self) = @_;
    $self->{'internal_store'}{'demousers_cache_time'} = time;
    $self->{'internal_store'}{'demousers'}            = {};

    if ( -e '/etc/demousers' ) {
        if ( open my $fh, '<', '/etc/demousers' ) {
            while ( my $line = readline($fh) ) {
                chomp $line;
                $self->{'internal_store'}{'demousers'}{$line} = 1;
            }
            close $fh;
        }
    }
    return 1;
}

sub _check_demodomains {
    my ($self) = @_;
    if ( !exists $self->{'internal_store'}{'demodomains_cache_time'} ) {
        $self->{'internal_store'}{'demodomains_cache_time'} = 0;
    }
    my $mtime = int( ( stat('/etc/demodomains') )[9] );
    if ( ( $self->{'internal_store'}{'demodomains_cache_time'} + 1800 ) < $mtime ) {
        return $self->_load_demousers();
    }
    return 1;
}

sub _load_demodomains {
    my ($self) = @_;
    $self->{'internal_store'}{'demodomains_cache_time'} = time;
    $self->{'internal_store'}{'demodomains'}            = {};

    if ( -e '/etc/demodomains' ) {
        if ( open my $fh, '<', '/etc/demodomains' ) {
            while ( my $line = readline($fh) ) {
                chomp $line;
                $self->{'internal_store'}{'demodomains'}{$line} = 1;
            }
            close $fh;
        }
    }
    return 1;
}

sub _migrate_relayhosts_to_recent_authed_mail_ips {
    my ($self) = @_;

    return 1 if ( $self->{'_relayhosts_is_linked'} && $self->{'_relayhostsusers_is_linked'} );
    if ( !$self->{'_relayhosts_is_linked'} ) {
        unlink('/etc/relayhosts');
        symlink( 'recent_authed_mail_ips', '/etc/relayhosts' );
        $self->{'_relayhosts_is_linked'} = 1;
    }
    if ( !$self->{'_relayhostsusers_is_linked'} ) {
        unlink('/etc/relayhostsusers');
        symlink( 'recent_authed_mail_ips_users', '/etc/relayhostsusers' );
        $self->{'_relayhostsusers_is_linked'} = 1;
    }
    return 1;
}

sub _check_conf {
    my ($self) = @_;

    if ( !exists $self->{'internal_store'}{'recentauthedmailiptracker_conf_cache_time'} ) {
        $self->{'internal_store'}{'recentauthedmailiptracker_conf_cache_time'} = 0;
    }
    my $mtime = int( ( stat($CONFIG_FILE_PATH) )[9] || 0 );
    if ( ( $self->{'internal_store'}{'recentauthedmailiptracker_conf_cache_time'} + 1800 ) < $mtime ) {
        return $self->_load_conf();
    }
    return 1;
}

sub _load_conf {
    my ($self) = @_;
    $self->{'internal_store'}{'recentauthedmailiptracker_conf_cache_time'} = time;
    $self->{'internal_store'}{'recentauthedmailiptracker_conf'}            = {};

    if ( -e $CONFIG_FILE_PATH ) {
        if ( open my $fh, '<', $CONFIG_FILE_PATH ) {
            while ( my $line = readline($fh) ) {
                chomp $line;
                if ( $line =~ m{ \A \s* ([\w\.]+) \s* [=] \s* (.*?) (?: \s* [;] .*)? \z }xms ) {
                    my $name  = $1;
                    my $value = $2;

                    if ( $value =~ m{ \A (["']) }xms ) {
                        my $quote = $1;
                        $value =~ s{ \A $quote (.*) $quote \z }{$1}xms;
                    }

                    $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{$name} = $value;
                }
            }
            close $fh;
        }
    }

    if ( !exists $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'expire_host_mins'} ) {
        $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'expire_host_mins'} = 30;
    }
    elsif ( $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'expire_host_mins'} !~ m{ \A \d+ \z}xms ) {
        $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'expire_host_mins'} = 30;
    }

    if ( !exists $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'recent_authed_mail_ips'} ) {
        $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'recent_authed_mail_ips'} = '/etc/recent_authed_mail_ips';
    }
    elsif ( !$self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'recent_authed_mail_ips'} || $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'recent_authed_mail_ips'} !~ m/^\/.+/ ) {
        warn "Invalid recent_authed_mail_ips setting in $CONFIG_FILE_PATH";
        $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'recent_authed_mail_ips'} = '/etc/recent_authed_mail_ips';
    }

    if ( !exists $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'recent_authed_mail_ips_users'} ) {
        $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'recent_authed_mail_ips_users'} = '/etc/recent_authed_mail_ips_users';
    }
    elsif ( !$self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'recent_authed_mail_ips_users'} || $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'recent_authed_mail_ips_users'} !~ m/^\/.+/ ) {
        warn "Invalid recent_authed_mail_ips_users setting in $CONFIG_FILE_PATH";
        $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'recent_authed_mail_ips_users'} = '/etc/recent_authed_mail_ips_users';
    }

    if ( !exists $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'alwaysrelay'} ) {
        $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'alwaysrelay'} = '/etc/alwaysrelay';
    }
    elsif ( !$self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'alwaysrelay'} || $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'alwaysrelay'} !~ m/^\/.+/ ) {
        warn "Invalid alwaysrelay setting in $CONFIG_FILE_PATH";
        $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'alwaysrelay'} = '/etc/alwaysrelay';
    }
    return 1;
}

sub _check_alwaysrelay {
    my ($self) = @_;
    if ( !exists $self->{'internal_store'}{'alwaysrelay_cache_time'} ) {
        $self->{'internal_store'}{'alwaysrelay_cache_time'} = 0;
    }
    my $mtime = int( ( stat( $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'alwaysrelay'} ) )[9] || 0 );
    if ( ( $self->{'internal_store'}{'alwaysrelay_cache_time'} + 1800 ) < $mtime ) {
        $self->_load_alwaysrelay();
    }
    return 1;
}

sub _load_alwaysrelay {
    my ($self) = @_;

    $self->{'internal_store'}{'alwaysrelay_cache_time'} = time();
    if ( open my $fh, '<', $self->{'internal_store'}{'recentauthedmailiptracker_conf'}{'alwaysrelay'} ) {
        local $/;
        $self->{'internal_store'}{'alwaysrelay'} = { map { $_ ne '.' ? ( split( /[=:\s]+/, $_ ) )[ 0, 1 ] : undef } split( /\r?\n/, readline($fh) ) };
        close $fh;
    }
    return 1;
}

1;
