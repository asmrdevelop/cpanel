package Cpanel::PackMan::Sys::yum;

# cpanel - Cpanel/PackMan/Sys/yum.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;    # must be after Moo

use Cpanel::ArrayFunc::Uniq ();
use Cpanel::RpmUtils::Parse ();
use Cpanel::Binaries::Yum   ();

# Provided by looks like [P_BY_PACKAGE_NAME, P_BY_VERSION, P_BY_RELEASE]
use constant P_BY_PACKAGE_NAME => 0;
use constant P_BY_VERSION      => 1;
use constant P_BY_RELEASE      => 2;

our $VERSION = "0.01";

with 'Role::Multiton';
extends 'Cpanel::PackMan::Sys';

has '+ext' => (
    is       => 'ro',
    init_arg => undef,
    default  => "rpm",
);

has '+subsystem' => (
    is       => 'ro',
    init_arg => undef,
    default  => 'rpm',
);

has '+jsoncmd_binary' => (
    is       => 'ro',
    init_arg => undef,
    default  => '/usr/local/cpanel/bin/python-packman',
);

has '+syscmd_binary' => (
    is       => 'ro',
    init_arg => undef,
    default  => '/usr/bin/yum',
);

has '+cmd_failure_hint' => (
    is       => 'ro',
    init_arg => undef,
    default  => 'yum makecache',
);

has '+repo_conf_pattern' => (
    is       => 'ro',
    init_arg => undef,
    default  => '/etc/yum.repos.d/%s.repo',
);

has '+universal_hooks_post_pkg_pattern' => (
    is       => 'ro',
    init_arg => undef,
    default  => "/etc/yum/universal-hooks/pkgs/%s/posttrans/%s",
);

my $yum_cmds_that_can_have_no_args = {
    "upgrade"   => 1,
    "update"    => 1,
    "makecache" => 1,
};

around syscmd => sub {
    my ( $orig, $self, $line_handler, $cmd, @args ) = @_;
    if ( !exists $yum_cmds_that_can_have_no_args->{$cmd} ) {
        return if !@args || ( $args[0] eq '-y' && @args == 1 );
    }

    # ZC-11464: Suppress color output even when always enabled in configuration:
    unshift @args, '--color=never';

    unshift @args, $cmd;
    my $lock = Cpanel::Binaries::Yum->new->get_lock_for_cmd( $self->logger, \@args );
    shift @args;

    return $orig->( $self, $line_handler, $cmd, @args );
};

sub syscmd_args_txn ( $self, $file ) {
    $self->_yummify_txn_file($file);
    return ( qw(-y shell), $file );
}

sub syscmd_args_txn_dryrun ( $self, $file ) {
    $self->_yummify_txn_file($file);
    return ( qw(--assumeno shell), $file );
}

sub _yummify_txn_file ( $self, $file ) {
    require Path::Tiny;
    my $po = Path::Tiny::path($file);
    $po->edit_lines( sub { s/^uninstall /erase / } );
    $po->append("run\n");
    return;
}

sub syscmd_line_indicates_headers_are_done ( $self, $line ) {
    return 2 if $line =~ m/package/i || _line_matches_error($line);    # in case end-of-header goes to/comes from oblivion
    return 1 if $line =~ m/^Finished\n$/ || $line =~ m/^Last metadata expiration check/ || $line =~ m/^Extra Packages/;
    return 0;
}

sub info ( $self, $pkg ) {
    my $hr = $self->jsoncmd( '/usr/local/cpanel/bin/packman_get_info_json', $pkg );
    return if !$hr || !keys %{$hr};

    return $hr;
}

sub multi_info ( $self, %args ) {
    my @args;
    push @args, '--populate-provides' if !exists $args{'populate-provides'} || $args{'populate-provides'};
    push @args, '--disable-excludes'  if $args{'disable-excludes'};
    push @args, map { ( '--package', $_ ) } @{ $args{packages} } if $args{packages};
    push @args, map { ( '--prefix',  $_ ) } @{ $args{prefixes} } if $args{prefixes};
    my $pkgs = $self->jsoncmd( '/usr/local/cpanel/bin/packman_get_multiinfo_json', @args );
    return if !$pkgs || ref $pkgs ne 'ARRAY';

    return $pkgs;
}

sub list ( $self, $type = "all", $prefix = undef ) {
    my $res = $self->jsoncmd( '/usr/local/cpanel/bin/packman_get_list_json', ( $prefix ? ( $type, $prefix ) : $type ) );
    return if !$res;

    return $res;
}

sub clean ($self) {
    return $self->syscmd( sub { return $_[0] }, "clean", "all" );
}

sub cache ($self) {
    return $self->syscmd( sub { return $_[0] }, "makecache" );
}

sub _expand_pkgs_to_args (@pkgs) {
    my $opts = ref( $pkgs[-1] ) ? pop(@pkgs) : {};

    my @args = @pkgs;

    if ( exists $opts->{only_from_repos} ) {
        die "`only_from_repos` given but it is not an array ref\n" if ref( $opts->{only_from_repos} ) ne 'ARRAY';
        die "`only_from_repos` given but it is empty\n"            if @{ $opts->{only_from_repos} } == 0;
        push @args, '--disablerepo=*', '--enablerepo=' . join( ",", @{ $opts->{only_from_repos} } );
    }

    return @args;
}

sub install ( $self, @pkgs ) {
    my @args = _expand_pkgs_to_args(@pkgs);
    return $self->syscmd( sub { return $_[0] }, "install", "-y", @args );
}

sub upgrade ( $self, @pkgs ) {
    my @args = _expand_pkgs_to_args(@pkgs);
    return $self->syscmd( sub { return $_[0] }, "upgrade", "-y", @args );
}

sub uninstall ( $self, @pkgs ) {
    return $self->syscmd( sub { return $_[0] }, "erase", "-y", @pkgs );
}

sub normalize_pkg_hr ( $self, $raw_hr ) {
    die if ref($raw_hr) ne 'HASH';

    my $res_hr = {
        package           => $raw_hr->{name},
        architecture      => $raw_hr->{arch},
        size              => $raw_hr->{size_installed},
        release           => $raw_hr->{release},
        version           => $raw_hr->{version},
        short_description => $raw_hr->{summary},
        long_description  => $raw_hr->{description},
        more_info_url     => $raw_hr->{url},
        license           => $raw_hr->{rpm_license},
        pkg_dep_raw       => {
            requires  => $raw_hr->{deplist},
            conflicts => $raw_hr->{conflicts},
        },
        repo_name         => 'NYI',                   # HB-227
        vendor            => 'NYI',
        pkg_group         => $raw_hr->{pkg_group},
        version_latest    => $raw_hr->{_latest},
        version_installed => $raw_hr->{_installed},
        state             => $raw_hr->{_state},
    };

    $res_hr->{pkg_dep} = $self->_normalize_pkg_dep_raw( $res_hr->{package}, $res_hr->{pkg_dep_raw} );
    delete $res_hr->{pkg_dep_raw} unless $ENV{PACKMAN_DEBUG};

    # Set 'state' to the same specific values that list() uses for 'state'.
    $res_hr->{state} = 'not_installed' if $res_hr->{state} && $res_hr->{state} eq 'available';
    if ( !$res_hr->{state} || ( $res_hr->{state} ne 'installed' && $res_hr->{state} ne 'updatable' && $res_hr->{state} ne 'not_installed' ) ) {
        if ( $self->is_installed($res_hr) ) {
            $res_hr->{state} = $self->is_uptodate($res_hr) ? 'installed' : 'updatable';
        }
        else {
            $res_hr->{state} = 'not_installed';
        }
    }

    return $res_hr;
}

sub parse_lines_for_errors ( $self, $lines_ar ) {
    my @errors;
    my $in_error               = 0;
    my $last_error_was_timeout = 0;

    foreach my $line ( @{$lines_ar} ) {
        chomp $line if $line;
        next        if !$line;    # In case all we had was a newline, then removed it, don't operate on it
        if ($last_error_was_timeout) {
            $last_error_was_timeout = 0;
            if ( $line =~ m/Trying other mirror/ ) {
                pop @errors;
            }
        }

        if ($in_error) {
            if ( $line =~ m/\A[ \t]/ ) {
                push( @errors, $line );
                next;
            }
            else {
                $in_error = 0;
            }
        }

        if ( _line_matches_error($line) ) {
            push( @errors, $line );
            $in_error = 1;
        }
        elsif ( $line =~ m/Errno\s+\d+/ ) {
            if ( $line =~ m/Timeout on/ ) {
                $last_error_was_timeout = 1;
            }
            push( @errors, $line );
        }
    }

    return @errors;
}

sub _line_matches_error ($line) {
    return $line =~ m/^Error: / || $line =~ m/No package .* available/i || $line =~ m/No match for argument/i || $line =~ m/Problem(?:\s+\d+)?:/ ? 1 : 0;
}

sub parse_syscmd_txn_output ( $self, $lines_ar, $trans_data ) {
    my $state = 'unknown';
    my @errors;
    my $in_error = 0;
    my $prev_line;
    foreach my $line ( @{$lines_ar} ) {

        if ($in_error) {
            if ( $line =~ m/\A[ \t]/ ) {
                if ( $line =~ m/Requires: / ) {
                    $in_error++;
                }
                elsif ( $in_error == 2 && $line =~ m/Removing: / ) {
                    my $removing = $line;
                    my $requires = $errors[-1];
                    $removing =~ s/.*Removing: (.+?)(?:\(|\-\d+|$).*/$1/s;
                    $requires =~ s/.*Requires: (.+?)(?:\(|\-\d+|$).*/$1/s;
                    if ( $removing eq $requires ) {
                        pop(@errors);
                        pop(@errors);
                        $in_error = 0;
                        $trans_data->{upgrade}{$removing} = 1;
                        next;
                    }
                }
                push( @errors, $line );
                next;
            }
            else {
                $in_error = 0;
            }
        }

        if ( $line =~ m/Installing(?:.*):/ ) {
            $state = 'install';
        }
        elsif ( $line =~ m/Updating:/ || $line =~ m/Upgrading:/ ) {
            $state = 'upgrade';
        }
        elsif ( $line =~ m/Removing:/ ) {
            $state = 'uninstall';
        }
        elsif ( $line =~ m/Reinstalling:/ ) {
            $state = 'unaffected';
        }
        elsif ( $line =~ m/Transaction Summary/ ) {
            last;
        }
        elsif ( $line =~ m/\s+(\S+)\s+(?:x86_64|i.86|noarch)/ ) {

            # Example lines
            #[yum] ea-apache24-mod_deflate       x86_64    2.4.23-2.2.1.cpanel       EA4     34 k
            #[dnf] yum-plugin-universal-hooks       x86_640.1-11.11.7.cpanel EA4 12k
            $trans_data->{$state}{$1} = 1;
        }
        elsif ( $line =~ m/\s+(?:x86_64|i.86|noarch)/ && defined $prev_line && $prev_line =~ m/^\s+(\S+)/ ) {
            $trans_data->{$state}{$1} = 1;
        }
        elsif ( $line =~ m/Package\s+(.+?)\s+is\s+obsoleted/ ) {
            my $pkg     = $1;
            my $pkgname = Cpanel::RpmUtils::Parse::parse_rpm_arch($pkg)->{'name'} || $pkg;
            $trans_data->{'install'}{$pkgname} = 1;
        }
        elsif ( $line =~ m/Package\s+(?:matching\s+)?(.+?)\s+already/ ) {    # Package ea-apache24-2.4.12-26.4.x86_64 already installed and latest version
            my $pkg     = $1;
            my $pkgname = Cpanel::RpmUtils::Parse::parse_rpm_arch($pkg)->{'name'} || $pkg;
            $trans_data->{'unaffected'}{$pkgname} = 1;
        }
        elsif ( $line =~ m/Package\s+(.+?)\.(?:x86_64|i.86|noarch).*\s+will be erased/ ) {    # ---> Package ea-php71-php-cli.x86_64 0:7.1.0-13.RC6.13.1.cpanel will be erased
            my $pkg = $1;
            $trans_data->{'uninstall'}{$pkg} = 1;
        }
        elsif ( $line =~ m/^Error: / || $line =~ m/No package .* available/i || $line =~ m/No match for argument/i || $line =~ m/Problem(?:\s+\d+):/ ) {
            push( @errors, $line );
            $in_error = 1;
        }
        else {
            $prev_line = $line;
        }
    }

    return;
}

sub is_unavailable ($self) {

    my $yum_pid_file = '/var/run/yum.pid';

    return 0 if ( !-e $yum_pid_file );

    require Cpanel::LoadFile;
    my $pid = Cpanel::LoadFile::loadfile($yum_pid_file);

    return 0 if ( !$pid );

    return 0 if ( $pid =~ /\D/ );

    return 0 if ( kill( 0, $pid ) == 0 );

    return 1;
}

###############
#### helpers ##
###############

sub _normalize_pkg_dep_raw ( $self, $pkg, $pkg_dep_raw ) {
    my $pkg_dep = {};

    #### normalize $pkg_dep_raw into $pkg_dep ##
    # make conflicts && requires contain only package names
    #     requires needs ability to and/or
    #     neither should contain itself
    #     neither should contain dupes (an or-list can contain a package that is in the main list or another or-list though)
    #     do not include conflicts that meet a requirement in the requires list

    # Conflicts looks like
    #      [
    #          {
    #            'provided_by' => [
    #                               [
    #   Extract this ===>             'ea-php99-php-recode' <======
    #                                 '5.6.24',
    #                                 '1.1.2.cpanel'
    #                               ]
    #                             ],
    #            'name' => 'ea-php99-php-recode'
    #          }
    #        ]

    $pkg_dep->{conflicts} = [
        Cpanel::ArrayFunc::Uniq::uniq(
            map {
                map {
                    $_->[P_BY_PACKAGE_NAME] ne $pkg ? $_->[P_BY_PACKAGE_NAME] : (),    # Can we really conflict with ourselves?
                } @{ $_->{'provided_by'} }
            } @{ $pkg_dep_raw->{conflicts} }
        )
    ];
    my %conflicting_packages_map = map { $_ => 1 } @{ $pkg_dep->{conflicts} };

    # Requires looks like
    #       [
    #          {
    #            'name' => 'rpmlib(FileDigests)',
    #            'provided_by' => []
    #          },
    #          {
    #            'name' => 'rpmlib(PayloadFilesHavePrefix)',
    #            'provided_by' => []
    #          },
    #          {
    #            'name' => 'rpmlib(CompressedFileNames)',
    #            'provided_by' => []
    #          },
    #          {
    #            'name' => 'libapr-1.so.0()(64bit)',
    #            'provided_by' => [
    #                               [
    #                                 'ea-apr',
    #                                 '1.5.2',
    #                                 '3.3.1'
    #                               ],
    #                               [
    #                                 'apr',
    #                                 '1.3.9',
    #                                 '5.el6_2'
    #                               ]
    #                             ]
    #          },
    #          {
    #            'name' => 'libaprutil-1.so.0()(64bit)',
    #            'provided_by' => [
    #                               [
    #                                 'ea-apr-util',
    #                                 '1.5.2',
    #                                 '11.11.1'
    #                               ],
    #                               [
    #                                 'apr-util',
    #                                 '1.3.9',
    #                                 '3.el6_0.1'
    #                               ]
    #                             ]
    #          },
    #          {
    #            'name' => 'libc.so.6()(64bit)',
    #            'provided_by' => [
    #                               [
    #                                 'glibc',
    #                                 '2.12',
    #                                 '1.192.el6'
    #                               ]
    #                             ]
    #          },

    $pkg_dep->{requires} = [];
    my %seen_require = ( $pkg => 1 );

    # Process all requires that have a single provider package
    # so we can add them to the seen_require list.  This allows
    # us to always pick the provider for the consumer
    # when there is an OR below
    foreach my $req ( grep { scalar @{ $_->{'provided_by'} } == 1 } @{ $pkg_dep_raw->{'requires'} } ) {
        my $package_name = $req->{'provided_by'}->[0]->[P_BY_PACKAGE_NAME];
        next if $conflicting_packages_map{$package_name} || $seen_require{$package_name};
        $seen_require{$package_name} = 1;
        push @{ $pkg_dep->{requires} }, $package_name;
    }

    # Multi providers - an OR statement
    #
    # *** ORDER MATTERS HERE ***
    # The providers are sorted by score from
    # yum's depsolve:_compare_providers so we need
    # to make sure keep the OR deps in the same order
    # as they were provided so we choose the best one
    #
    foreach my $req ( grep { scalar @{ $_->{'provided_by'} } > 1 } @{ $pkg_dep_raw->{'requires'} } ) {
        #
        # If one of the other required packages already provides this we do not need
        # to have them choose as it will already be provided
        #
        next if ( grep { $_->[P_BY_PACKAGE_NAME] ne $pkg && $seen_require{ $_->[P_BY_PACKAGE_NAME] } } @{ $req->{provided_by} } );
        #
        # If the package conflicts one of the providers eliminate it from the
        # list since installing it is futile
        #
        my @potential_providers = Cpanel::ArrayFunc::Uniq::uniq( map { $_->[P_BY_PACKAGE_NAME] } grep { $_->[P_BY_PACKAGE_NAME] ne $pkg && !$conflicting_packages_map{ $_->[P_BY_PACKAGE_NAME] } } @{ $req->{provided_by} } );

        # If we are down to one provider we know which one to require
        if ( scalar @potential_providers == 1 ) {

            # We have narrowed it down to one provider
            my $package_name = $potential_providers[0];
            push @{ $pkg_dep->{requires} }, $package_name;
            $seen_require{$package_name} = 1;
        }

        # Otherwise we need to over them a choice by pushing
        # in an arrayref
        else {
            push @{ $pkg_dep->{requires} }, \@potential_providers;
        }
    }

    return $pkg_dep;
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::PackMan::Sys::yum - Implements yum support for Cpanel::PackMan

=head1 VERSION

This document describes Cpanel::PackMan::Sys::yum version 0.01

=head1 SYNOPSIS

Do not use directly. Instead use L<Cpanel::PackMan>.

=head1 DESCRIPTION

Subclass of L<Cpanel::PackMan::Sys> implementing C<dnf> support for PackMan.

