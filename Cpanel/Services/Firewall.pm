package Cpanel::Services::Firewall;

# cpanel - Cpanel/Services/Firewall.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::OS                          ();
use Cpanel::Binaries                    ();
use Cpanel::ConfigFiles                 ();
use Cpanel::Config::LoadCpConf          ();
use Cpanel::RestartSrv::Systemd         ();
use Cpanel::SafeRun::Simple             ();
use Cpanel::Services::Ports::Authorized ();
use Cpanel::FileUtils::Write            ();
use Cpanel::FileUtils::Read             ();
use Cpanel::SafeRun::Dynamic            ();
use Cpanel::JSON                        ();

use constant ULC                => $Cpanel::ConfigFiles::CPANEL_ROOT;
use constant FIREWALLD_SERVICES => q{/etc/firewalld/services};

# for mocking purpose
our $CPANEL_FIREWALLD_SERVICE = FIREWALLD_SERVICES . q{/cpanel.xml};

my $port_authority_name = "cP-Firewall-1-PortAuthority";
our $has_port_authority_chain = 0;

sub is_firewalld {
    return Cpanel::OS::is_systemd() && Cpanel::RestartSrv::Systemd::has_service_via_systemd('firewalld') && _is_firewalld_active() ? 1 : 0;
}

sub setup_firewall {

    my $hr           = { Cpanel::Config::LoadCpConf::loadcpconf() };
    my $skipfirewall = $hr->{'skip_rules_added_by_configure_firewall_for_cpanel'};

    return _set_firewall_with_systemd() if is_firewalld();

    if ( Cpanel::OS::firewall_module() eq 'NFTables' ) {
        return _set_firewall_with_nftables($skipfirewall);
    }

    my $ok     = 0;
    my $status = 1;

    if ( -x Cpanel::Binaries::path("iptables") ) {
        $status &= _set_firewall_with_iptables($skipfirewall);
        $ok = $status;
    }
    if ( -x Cpanel::Binaries::path("ip6tables") ) {
        $status &= _set_firewall_with_ip6tables($skipfirewall);
        $ok = $status;
    }

    return $ok;
}

sub _get_cmds {
    my (@search) = @_;
    my %cmds;

    foreach my $exe (@search) {
        $cmds{$exe} = Cpanel::Binaries::path($exe);
        -x $cmds{$exe} or die qq[Cannot find $cmds{$exe}];
    }
    return \%cmds;
}

sub _warn {
    my (@msg) = @_;
    print STDERR join ' ', @msg, "\n";
    return;
}

sub _is_firewalld_active {
    my $status = eval { Cpanel::RestartSrv::Systemd::get_status_via_systemd('firewalld') || 0 };
    return 1 if $status && $status eq 'active';
    return 0;
}

# ===== systemd logic ========
# create cPanel service
# /usr/lib/firewalld/services/cpanel.xml
sub _set_firewall_with_systemd {

    my $cmd = _get_cmds(qw/systemctl firewall-cmd/);

    if ( !_is_firewalld_active() ) {
        _warn(q{The firewalld service is currently inactive. To enable and start the firewalld service before you configure it, ensure the service is unmasked, then run the following commands: systemctl enable firewalld && systemctl start firewalld});
        return 1;
    }

    # could also use the zone for th0: firewall-cmd --get-zone-of-interface=eth0
    my $default_zone = Cpanel::SafeRun::Simple::saferunnoerror( $cmd->{'firewall-cmd'}, '--get-default-zone' );
    if ( $? || !$default_zone ) {
        _warn("The system cannot get the firewall's default-zone. Is the 'firewalld.service' running?");
        return 1;
    }
    chomp $default_zone;

    # update ( or write for the 1st time ) cpanel service
    my $has_file = -e $CPANEL_FIREWALLD_SERVICE ? 1 : 0;
    Cpanel::FileUtils::Write::overwrite_no_exceptions( $CPANEL_FIREWALLD_SERVICE, cpanel_firewalld_service_content(), 0640, 0 );

    # need to reload the service when cpanel service is installed for the 1st time
    if ( !$has_file ) {
        Cpanel::SafeRun::Simple::saferunnoerror( $cmd->{'systemctl'}, 'restart', 'firewalld' );

        # Cpanel::SafeRun::Simple::saferunnoerror( $cmd->{'systemctl'}, 'reload', 'firewalld' );
        # Cpanel::SafeRun::Simple::saferunnoerror( $cmd->{'firewall-cmd'}, '--reload' );
    }

    # [Nice to have] Factor in port authority conf here (or in cpanel_firewalld_service_content()).
    #                - At the same time remove scripts/cpuser_port_authority’s _get_firewalld_caveat() stuff

    # enable cpanel service
    Cpanel::SafeRun::Simple::saferunnoerror( $cmd->{'firewall-cmd'}, '--permanent', '--zone=' . $default_zone, '--add-service=cpanel', '-q' );

    # reload firewalld
    Cpanel::SafeRun::Simple::saferunnoerror( $cmd->{'firewall-cmd'}, '--reload' );

    return $?;
}

sub cpanel_firewalld_service_content {
    my $ports_by_protocol = Cpanel::Services::Ports::Authorized::allowed_ports_by_protocol();
    my $pa_hr             = _get_port_authority_conf();

    my $ports_rules = '';
    foreach my $protocol ( sort keys %$ports_by_protocol ) {
        foreach my $port ( @{ $ports_by_protocol->{$protocol} }, sort keys %{$pa_hr} ) {

            # iptables expects port:port and firewalld expects port-port.
            # in Cpanel::Services::Ports::Authorized, it's expressed with a colon
            # because iptables won the coin toss.
            $port =~ tr/:/-/;
            $ports_rules .= qq{  <port protocol="$protocol" port="$port"/>\n};
        }
    }

    return <<"EOS";
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>cPanel</short>
  <description>This option allows you to access cPanel &amp; WHM's standard services.</description>
$ports_rules</service>
EOS
}

sub _allowed_ports {
    my %allowed = (
        'tcp' => [ Cpanel::Services::Ports::Authorized::allowed_tcp_ports() ],
        'udp' => [ Cpanel::Services::Ports::Authorized::allowed_udp_ports() ],
    );
    return \%allowed;
}

# ===== nftables logic ========
sub _set_firewall_with_nftables {
    my ($skipfirewall) = @_;

    my $nftables_cmd  = Cpanel::Binaries::path("nft");
    my $allowed_ports = _allowed_ports();
    my ( @temp_tcp, @temp_udp );

    # Order is important, first come first serve
    my @lines_to_insert = (
        [qw'add table inet filter'],
        [qw'add chain inet filter INPUT { type filter hook input priority 0; policy accept; }'],
        [qw'add chain inet filter FORWARD { type filter hook forward priority 0; policy accept; }'],
        [qw'add chain inet filter OUTPUT { type filter hook output priority 0; policy accept; }'],
        [qw'add chain inet filter cPanel-HostAccessControl'],
        [qw'add rule inet filter INPUT counter jump cPanel-HostAccessControl'],
        [qw'add rule inet filter FORWARD counter jump cPanel-HostAccessControl'],
    );
    push @lines_to_insert, (
        [qw'add chain inet filter cP-Firewall-1-INPUT'],
        [qw'add rule inet filter INPUT counter jump cP-Firewall-1-INPUT'],
        [qw'add rule inet filter FORWARD counter jump cP-Firewall-1-INPUT'],
    ) unless $skipfirewall;

    # Don't save if it looks like the current ruleset hasn't been loaded.
    require Cpanel::XTables;
    require Cpanel::NFTables;
    my $nft_obj       = Cpanel::XTables->new( 'chain' => $skipfirewall ? 'cPanel-HostAccessControl' : 'cP-Firewall-1-INPUT' );
    my $current_rules = $nft_obj->get_all_rules() || [];
    my $conf_file     = Cpanel::OS::nftables_config_file();
    my $read_only     = ( !-z $conf_file && scalar(@$current_rules) ? 1 : 0 );

    my @port_authority_rules      = ();
    my $port_authority_conf_mtime = _get_port_authority_conf_mtime();

    my $s = ( stat $conf_file )[9];
    if ( ( ( $port_authority_conf_mtime && $s ) && ( $port_authority_conf_mtime > $s ) ) || $has_port_authority_chain ) {
        @port_authority_rules = _get_port_authority_rules('nftables');
    }

    # Rules for nftables
    my $nftables_rules = [
        @lines_to_insert,
    ];
    push @$nftables_rules, (
        (
            map {
                my $p = $_;
                $p =~ s/:/-/;    # Ranges use - instead of colon
                [ qw'add rule inet filter cP-Firewall-1-INPUT ct state new tcp dport', $p, qw'counter accept' ]
            } @{ $allowed_ports->{'tcp'} }
        ),
        (
            map {
                my $p = $_;
                $p =~ s/:/-/;    # Ranges use - instead of colon
                [ qw'add rule inet filter cP-Firewall-1-INPUT ct state new udp dport', $p, qw'counter accept' ]
            } @{ $allowed_ports->{'udp'} }
        ),
        @port_authority_rules,
    ) unless $skipfirewall;

    if (@$nftables_rules) {

        # nftables ignores dupes, so this makes our life easy.
        # Eval the flush, as it may not be needed (no table exists)
        if ( $nft_obj->table_exists( family => q[inet], name => q[filter] ) ) {
            local $@;
            eval { $nft_obj->exec_checked_calls( [ [qw{flush table inet filter}] ] ) };
            _warn($@) if $@;
        }
        $nft_obj->exec_checked_calls($nftables_rules);

        # Persist the ruleset so that it exists on reboot
        $nft_obj->save_current_ruleset();

        # Enable the service so reboots reload rules
        Cpanel::SafeRun::Simple::saferunnoerror(qw{/bin/systemctl enable nftables.service});

        # If we save the service when it's down, we might blow away the user's ruleset.
        if ( !$read_only ) {
            Cpanel::SafeRun::Simple::saferunnoerror(qw{/bin/systemctl restart nftables.service});
        }

        return $?;
    }

    return;
}

# ===== iptables logic ========
sub _set_firewall_with_iptables {
    my ($skipfirewall) = @_;
    return if $skipfirewall;

    my $cmd = _get_cmds(qw/iptables iptables-save/);

    return _setup_with_iptables( 'iptables', $cmd ) || 0;
}

sub _set_firewall_with_ip6tables {
    my ($skipfirewall) = @_;
    return if $skipfirewall;

    my $cmd = _get_cmds(qw/ip6tables ip6tables-save/);

    # map binaries to use common logic
    $cmd->{'iptables'}      = $cmd->{'ip6tables'};
    $cmd->{'iptables-save'} = $cmd->{'ip6tables-save'};

    return _setup_with_iptables( 'ip6tables', $cmd ) || 0;
}

sub _get_conf_file {
    my ($iptables_cmd) = @_;
    return $iptables_cmd =~ /ip6tables/ ? Cpanel::OS::iptables_ipv6_savefile() : Cpanel::OS::iptables_ipv4_savefile();
}

sub _setup_with_iptables {
    my ( $service, $cmd ) = @_;

    my $iptables_cmd      = $cmd->{'iptables'};
    my $iptables_save_cmd = $cmd->{'iptables-save'};
    my $allowed_ports     = _allowed_ports();

    my ( @temp_tcp, @temp_udp );

    my @lines_to_insert = (
        "INPUT -j cP-Firewall-1-INPUT",
        "FORWARD -j cP-Firewall-1-INPUT",
    );

    # Don't save if it looks like the current ruleset hasn't been loaded.
    my @current_rules = grep { /^\-A/ } split /\n/, Cpanel::SafeRun::Simple::saferunnoerror( $iptables_cmd, '-S' );
    my $conf_file     = _get_conf_file($iptables_cmd);
    my $read_only     = ( !-z $conf_file && $#current_rules == -1 ) ? 1 : 0;

    Cpanel::SafeRun::Dynamic::livesaferun(
        'prog'      => [$iptables_save_cmd],
        'formatter' => sub {
            my ($line) = @_;
            chomp $line;

            return if ( $line !~ /^-A/ );
            if ( $line =~ m/-A OUTPUT -j \Q$port_authority_name\E/ ) {
                $has_port_authority_chain++;
            }

            # If we already have an entry matching this line, remove it from the
            # list of lines to insert so we don't insert a duplicate.
            foreach my $insert_line (@lines_to_insert) {
                if ( index( $line, "-A $insert_line" ) != -1 ) {
                    @lines_to_insert = grep { $_ ne $insert_line } @lines_to_insert;
                    return;
                }
            }

            # if the user has any rules in place for that port, we should avoid whitelisting that port via our chain
            foreach my $port ( @{ $allowed_ports->{'tcp'} } ) {
                if ( $line =~ /^-A\s+(?:cP-Firewall-1-)?INPUT.*tcp.*$port.*-j\s+(?:ACCEPT|DROP)/ ) {
                    push @temp_tcp, $port;
                }
            }

            # if the user has any rules in place for that port, we should avoid whitelisting that port via our chain
            foreach my $udp_port ( @{ $allowed_ports->{'udp'} } ) {
                if ( $line =~ /^-A\s+(?:cP-Firewall-1-)?INPUT.*udp.*$udp_port.*-j\s+(?:ACCEPT|DROP)/ ) {
                    push @temp_udp, $udp_port;
                }
            }

            return;
        }
    );

    # Remove ports from @allow_tcp_ports that exist in @temp_tcp (ports already configured w/ iptables).
    my %tcp_diff;
    @tcp_diff{ @{ $allowed_ports->{'tcp'} } } = @{ $allowed_ports->{'tcp'} };
    delete @tcp_diff{@temp_tcp};
    @{ $allowed_ports->{'tcp'} } = ( keys %tcp_diff );

    # Same for UDP ports.
    my %udp_diff;
    @udp_diff{ @{ $allowed_ports->{'udp'} } } = @{ $allowed_ports->{'udp'} };
    delete @udp_diff{@temp_udp};
    @{ $allowed_ports->{'udp'} } = ( keys %udp_diff );

    my @port_authority_rules      = ();
    my $port_authority_conf_mtime = _get_port_authority_conf_mtime();

    # If the port authority file is more recent than the config file
    # Or, if we the have port authority items in the config, and the port authority file has been deleted
    # Then we need to load the port authority rules
    if ( ( $port_authority_conf_mtime > ( stat $conf_file )[9] ) || $has_port_authority_chain ) {
        @port_authority_rules = _get_port_authority_rules();
    }

    # Rules for iptables
    my $iptables_rules = [
        ( map { /^(\S+)\s+(.*)$/; "-I $1 1 $2" } @lines_to_insert ),
        ( map { "-A cP-Firewall-1-INPUT -m state --state NEW -m tcp -p tcp --dport $_ -j ACCEPT" } @{ $allowed_ports->{'tcp'} } ),
        ( map { "-A cP-Firewall-1-INPUT -m state --state NEW -m udp -p udp --dport $_ -j ACCEPT" } @{ $allowed_ports->{'udp'} } ),
        @port_authority_rules,
    ];

    if (@$iptables_rules) {

        unshift @$iptables_rules, "-N cP-Firewall-1-INPUT";

        foreach my $rule (@$iptables_rules) {
            system $iptables_cmd, split / /, $rule;
        }

        # If we save the service when it's down, we might blow away the user's ruleset.
        if ( !$read_only ) {
            _write_iptables_rules_to_savefile( $service, $iptables_cmd, $conf_file );
            system Cpanel::Binaries::path('service'), $service, 'restart';
        }

        return $?;
    }

    return;
}

sub _write_iptables_rules_to_savefile {
    my ( $service, $iptables_cmd, $conf_file ) = @_;

    if ( -x "/etc/init.d/$service" ) {
        Cpanel::SafeRun::Simple::saferun( "/etc/init.d/$service", 'save' );
    }
    elsif ( -x '/usr/sbin/netfilter-persistent' ) {

        # This Ubuntu(?) script has a system of plugins. When saving v4 rules, instruct the v6 plugin to ignore the command, and v.v.
        my $env_var = uc( $service eq 'iptables' ? 'ip6tables' : 'iptables' ) . '_SKIP_SAVE';
        local $ENV{$env_var} = 'yes';

        Cpanel::SafeRun::Simple::saferun( '/usr/sbin/netfilter-persistent', 'save' );
    }
    else {
        my $output = '';
        if ( -x "$iptables_cmd-save" ) {
            $output = Cpanel::SafeRun::Simple::saferun("$iptables_cmd-save");
        }
        else {
            my $service_insert_underscore = $service =~ s/tables$/_tables/r;
            my $proc_file_path            = '/proc/net/' . $service_insert_underscore . '_names';    # These files seem to indicate which tables are loaded.
            Cpanel::FileUtils::Read::for_each_line(
                $proc_file_path,
                sub {
                    my $iter  = shift;
                    my $table = $_;
                    chomp $table;

                    $output .= "*$table\n";
                    $output .= Cpanel::SafeRun::Simple::saferun( $iptables_cmd, '--table', $table, '--list-rules' );
                    $output .= "COMMIT\n";

                    $iter->stop();
                }
            );
        }
        Cpanel::FileUtils::Write::overwrite_no_exceptions( $conf_file, $output, 0640 );
    }

    return;
}

sub _get_port_authority_conf_mtime {

    # this both tests if the file exists and is valid
    my $hr = _get_port_authority_conf();

    # empty conf implies absent or invalid file, return 0 for mtime
    if ( !%$hr ) {
        return 0;
    }

    return ( stat $scripts::cpuser_port_authority::port_authority_conf )[9] // 0;
}

sub _get_port_authority_conf {
    if ( !defined $scripts::cpuser_port_authority::port_authority_conf ) {
        require "/usr/local/cpanel/scripts/cpuser_port_authority";    ## no critic qw(Modules::RequireBarewordIncludes)
    }
    my $hr = eval { Cpanel::JSON::LoadFile($scripts::cpuser_port_authority::port_authority_conf) } || {};
    return $hr;
}

sub _get_port_authority_rules {
    my ($rule_type) = @_;
    my @port_authority_rules;
    my $hr = _get_port_authority_conf();

    if ( $rule_type && $rule_type eq 'nftables' ) {
        push @port_authority_rules, "add chain inet filter $port_authority_name";
        foreach my $proto (qw{tcp udp}) {
            foreach my $port ( keys %{$hr} ) {
                push @port_authority_rules, "add rule inet filter $port_authority_name $proto sport $port counter reject";
                push @port_authority_rules, "add rule inet filter $port_authority_name $proto sport $port skuid $hr->{$port}{owner} counter accept";
            }
        }
    }
    else {    # Fallback to iptables
        @port_authority_rules = ("-F $port_authority_name");    # always flush

        if ( keys %{$hr} ) {
            push @port_authority_rules, "-N $port_authority_name";
            if ( !$has_port_authority_chain ) {
                push @port_authority_rules, "-I OUTPUT 1 -j $port_authority_name";
            }

            for my $port ( sort keys %{$hr} ) {
                for my $proto (qw(tcp udp)) {
                    push @port_authority_rules,
                      "-I $port_authority_name -p $proto --sport $port -j REJECT",
                      "-I $port_authority_name -p $proto --sport $port -m owner --uid-owner $hr->{$port}{owner} -j ACCEPT";
                }
            }
        }
    }

    return @port_authority_rules;
}

1;
