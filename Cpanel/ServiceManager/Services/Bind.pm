package Cpanel::ServiceManager::Services::Bind;

# cpanel - Cpanel/ServiceManager/Services/Bind.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# ABSTRACT: Manage named via restartsrv
# PODNAME: Cpanel::ServiceManager::Services::Bind

=head1 SYNOPSIS

    use Cpanel::ServiceManager::Services::Bind;

    my $obj = Cpanel::ServiceManager::Services::Bind->new();

    $obj->start();

=head1 DESCRIPTION

C<Cpanel::ServiceManager::Services::Bind> extends L<Cpanel::ServiceManager::Base> with BIND related functionality.

=cut

use Moo;
use cPstrict;

extends 'Cpanel::ServiceManager::Base';

use Cpanel::Logger                  ();
use Cpanel::RestartSrv::Systemd     ();
use Cpanel::Chkservd::Tiny          ();
use Cpanel::DNSLib::Check           ();
use Cpanel::FindBin                 ();
use Cpanel::NameServer::Utils::BIND ();
use Cpanel::ServiceManager::Base    ();
use Cpanel::OS                      ();
use Cpanel::PwCache                 ();

has '_flag_init_update' => ( is => 'ro', default => '/var/cpanel/version/named_init_update' );
has '_init_file' => ( is => 'ro', lazy => 1, default => sub { return Cpanel::RestartSrv::Systemd::has_service_via_systemd('named') ? q{/usr/lib/systemd/system/named.service} : q{/etc/init.d/named} } );

has '+is_configured'  => ( is => 'rw', lazy => 1, default => sub { $_[0]->cpconf->{'local_nameserver_type'} eq 'bind' ? 1 : 0 } );
has '+is_enabled'     => ( is => 'rw', lazy => 1, default => sub { return 0 if $_[0]->cpconf->{'local_nameserver_type'} ne 'bind'; return $_[0]->SUPER::is_enabled() } );
has '+service_binary' => ( is => 'rw', lazy => 1, default => sub { Cpanel::FindBin::findbin('named') } );
has '+ports'          => ( is => 'ro', lazy => 1, default => sub { [53] } );

has '+service_package' => ( is => 'ro', default => 'bind' );
has '+pidfile'         => ( is => 'ro', default => '/var/run/named/named.pid' );
has '+processowner'    => ( is => 'ro', default => 'named' );
has '+startup_timeout' => ( is => 'ro', default => 60 );

=head1 SUBROUTINES

=head2 B<service>

Returns the string 'named'. Don't change this or things will fail for strange reasons.

=cut

sub service {
    return 'named';
}

=head2 B<BUILD>

Constructs the object. Technically? an internal method, as I see no reason you'd want to call this directly.

=cut

sub BUILD {
    my ($self) = @_;

    return unless $self->cpconf->{'local_nameserver_type'} eq 'bind';

    $self->check_init_script();

    return;
}

=head2 B<check>

Returns truthy status about whether named is 'up' or not..

=cut

sub check {
    my $self = shift;

    return 0 if !$self->SUPER::check(@_);

    my $namedconf = Cpanel::NameServer::Utils::BIND::find_namedconf();
    my @PATH      = split( /\//, $namedconf );
    pop @PATH;
    my $conf_dir = join( '/', @PATH );
    my ( $chrootdir, $binduser, $bindgroup ) = Cpanel::NameServer::Utils::BIND::find_chrootbinddir();
    my $binduid = ( Cpanel::PwCache::getpwnam($binduser) )[2];
    my $bindgid = ( getgrnam($bindgroup) )[2];

    if ( $binduid && $bindgid ) {
        my @confs;
        foreach my $file ( $namedconf, $conf_dir . '/rndc.key', $conf_dir . '/rndc.conf' ) {
            if ( -e $file && !-l $file ) {
                push @confs, $file;
            }
            if ($chrootdir) {
                my $f = $chrootdir . '/' . $file;
                if ( -e $f && !-l $f ) {
                    push @confs, $f;
                }
            }
        }
        foreach my $conf (@confs) {
            $conf =~ s/\/+/\//g;
            my ( $confuid, $confgid ) = ( stat($conf) )[ 4, 5 ];
            if ( $confuid != $binduid || $confgid != $bindgid ) {
                chown $binduid, $bindgid, $conf;
                $self->logger()->info("The system fixed the '$conf' file's ownership.");    #print something so named gets restarted
            }
        }
    }

    if ( !Cpanel::DNSLib::Check::checkrndc() ) {
        $self->logger()->warn( $self->service() . ": call to rndc failed\n" );
        $self->reinstall_named_init_script_for_portrelease();
        return 0;
    }

    return 1;
}

=head2 B<start>

Attempts to start named, returns an array of output of the start subroutine.

=cut

sub start {
    my ( $self, @args ) = @_;
    $self->suspend_chkservd();    # suspend chkservd
    my @out = $self->SUPER::start(@args);
    $self->resume_chkservd();     # resume chkservd
    return @out;
}

=head2 B<suspend_chkservd>

Temporarily turn off monitoring while restarting.

=cut

sub suspend_chkservd {
    Cpanel::Chkservd::Tiny::suspend_service( 'named', 3600 );
    return;
}

=head2 B<resume_chkservd>

Turn checksrvd back on, ideally after calling suspend_chkservd.

=cut

sub resume_chkservd {
    Cpanel::Chkservd::Tiny::resume_service('named');
    return;
}

sub _parse_systemd_file {
    my ($init_fh) = @_;

    # extract from /usr/lib/systemd/system/named.service on a CentOS 7 system
    # ExecStartPre=/usr/sbin/named-checkconf -z /etc/named.conf

    my $need_update;
    my @updated_lines;

    while ( my $line = readline $init_fh ) {
        if ( $line =~ m{\bnamed-checkconf\b} && $line =~ m{\s-z\s} ) {
            $need_update = 1;
            $line =~ s{\s\-z(\s)}{$1};
        }
        push @updated_lines, $line;
    }

    return $need_update ? \@updated_lines : undef;
}

sub _parse_systemv_file {
    my ($init_fh) = @_;

    my @initd_named;

    # Flag changes for write
    my $removed_checkzone_option = 0;

    while ( my $line = readline $init_fh ) {

        # Check for checkzone option during restarts
        if ( !$removed_checkzone_option && $line =~ m/^\s*ckcf_options=/ && ( $line =~ m/^(\s*)ckcf_options=["']([^'"]+)["'](.*)$/s || $line =~ m/^(\s*)ckcf_options=([^"'\s;]+)(.*)$/s ) ) {
            my ( $line_beginning, $options, $line_ending ) = ( $1, $2, $3 );

            # Only concerned if '-z' option is present
            if ( $options =~ m/\-z/ ) {
                $options =~ s/^["']//;
                $options =~ s/["']$//;
                my @options_array = split( /\s+/, $options );

                my $options_count = scalar @options_array;
                @options_array = grep { $_ ne '-z' } @options_array;

                # Check to see if '-z' was removed explicitly as we may end up here when the option was '-zwhatever'
                if ( $options_count != scalar @options_array ) {
                    $removed_checkzone_option = 1;
                    push @initd_named, $line_beginning . q{ckcf_options='} . join( ' ', @options_array ) . q{'} . $line_ending;
                }
                else {
                    push @initd_named, $line;
                }
            }
            else {
                push @initd_named, $line;
            }
        }
        else {
            push @initd_named, $line;
        }
    }

    return $removed_checkzone_option ? \@initd_named : undef;
}

# return codes only used for unit test purpose
sub check_init_script {
    my $self = shift;

    my $flag_file      = $self->_flag_init_update;
    my $bind_init_file = $self->_init_file;
    my $is_systemd     = $bind_init_file =~ m{\bsystemd\b} ? 1 : 0;

    # Can't use $self->logger because we're called from BUILD and it might not
    # be set up yet.
    my $logger = Cpanel::Logger->new;

    return unless -e $bind_init_file;
    my $init_mtime = ( stat(_) )[9];

    if ( -e $flag_file ) {
        my $flag_mtime = ( stat(_) )[9];
        return -1 if $flag_mtime == $init_mtime;
    }

    if ( open my $init_fh, '+<', $bind_init_file ) {

        my $updated_lines;
        if ($is_systemd) {
            $updated_lines = _parse_systemd_file($init_fh);
        }
        else {
            $updated_lines = _parse_systemv_file($init_fh);
        }

        # Only write the file if we've changed something
        if ( defined $updated_lines && ref $updated_lines eq 'ARRAY' ) {
            $logger->info("Updating '$bind_init_file' file to remove the -z option from named-checkconf call");
            seek( $init_fh, 0, 0 );
            print {$init_fh} join( '', @$updated_lines );
            truncate( $init_fh, tell($init_fh) );
        }
        close $init_fh;

        # reload the daemon on a systemd
        system( '/usr/bin/systemctl', 'daemon-reload' ) if defined $updated_lines && $is_systemd && -x q{/usr/bin/systemctl};

        # Update the flag file and init file for the same time
        system( 'touch', '-r', $bind_init_file, $flag_file );

        return 1;
    }
    else {
        $logger->warn("Failed to open $bind_init_file for read write: $!");
    }

    return 2;
}

# only for init.d systems.
sub reinstall_named_init_script_for_portrelease {
    my $self = shift;

    return if Cpanel::OS::is_systemd();

    require Cpanel::Init;
    require Cpanel::LoadFile;

    my $init = Cpanel::Init->new();

    my $init_file = $init->init_dir . '/named';

    return unless -e $init_file;

    my $load = Cpanel::LoadFile::loadfile($init_file);
    if ( !defined $load || $load !~ m/portrelease/ ) {
        $self->logger()->info("Reinstalling named init script (portrelease call missing)...");
        $init->run_command_for_one( 'install', 'named' );
        $self->logger()->info("...Done\n");
        return 1;
    }
    return;
}

1;
