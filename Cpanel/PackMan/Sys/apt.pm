package Cpanel::PackMan::Sys::apt;

# cpanel - Cpanel/PackMan/Sys/apt.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;    # must be after Moo

use Cpanel::ArrayFunc::Uniq ();

use Cpanel::Binaries::Debian::Apt      ();    # PPI USE OK - dynamically used by get_syscmd_lock
use Cpanel::Binaries::Debian::AptCache ();    # PPI USE OK - dynamically used by get_syscmd_lock
use Cpanel::Binaries::Debian::AptGet   ();    # PPI USE OK - dynamically used by get_syscmd_lock

use Cpanel::SafeRun::Object ();

use Text::Glob ();

our $VERSION = "0.01";

extends 'Cpanel::PackMan::Sys';

has '+ext' => (
    is       => 'ro',
    init_arg => undef,
    default  => "deb",
);

has '+subsystem' => (
    is       => 'ro',
    init_arg => undef,
    default  => 'dpkg',
);

has '+jsoncmd_binary' => (
    is       => 'ro',
    init_arg => undef,
    default  => '/usr/local/cpanel/bin/packman-apt.pl',
);

has '+syscmd_binary' => (
    is       => 'ro',
    init_arg => undef,
    default  => '/usr/bin/apt-get',    # no ansi color, can override when needed (e.g. apt-cache)
);

has '+cmd_failure_hint' => (
    is       => 'ro',
    init_arg => undef,
    default  => 'apt update',
);

has '+repo_conf_pattern' => (
    is       => 'ro',
    init_arg => undef,
    default  => '/etc/apt/sources.list.d/%s.list',
);

has '+universal_hooks_post_pkg_pattern' => (
    is       => 'ro',
    init_arg => undef,
    default  => "/etc/apt/universal-hooks/pkgs/%s/Post-Invoke/%s",
);

my %apt_subcmd_alt_bin = (
    search  => '/usr/bin/apt-cache',
    show    => '/usr/bin/apt-cache',
    depends => '/usr/bin/apt-cache',
    list    => '/usr/bin/apt',         # ansi color always :( ➜ -o APT::Color=0 :)
);

my %apt_subcmd_yesflag = (
    autoremove => 1,
    install    => 1,
    upgrade    => 1,
    remove     => 1,
    purge      => 1,
);

around syscmd => sub {
    my ( $orig, $self, $line_handler, $cmd, @args ) = @_;

    state @non_interactive_config_options = qw(-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold);
    state @apt_bin_plainify_options       = qw(-o Dpkg::Progress=0 -o Dpkg::Progress-Fancy=0 -o APT::Color=0);           # https://github.com/Debian/apt/search?q=Dpkg%3A%3AProgress

    # no good way to local() an attribute so here is a gross hack
    local $self->{syscmd_binary} = $apt_subcmd_alt_bin{$cmd} // $self->syscmd_binary;

    my $lock_to_hold = $self->get_syscmd_lock_for_cmd( [ $cmd, @args ] );

    local $ENV{DEBIAN_FRONTEND} = "noninteractive";
    local $ENV{DEBIAN_PRIORITY} = "critical";

    # if not all support --quiet then we’ll need a lookup hash and to implement
    #   syscmd_line_indicates_headers_are_done() for the ones that do not
    # if not all support @non_interactive_config_options we’ll need a lookup hash
    return $orig->(
        $self, $line_handler, $cmd, "--quiet",
        ( $apt_subcmd_yesflag{$cmd}                ? "--yes"                   : () ),
        ( $self->{syscmd_binary} eq '/usr/bin/apt' ? @apt_bin_plainify_options : () ),
        @non_interactive_config_options, @args
    );
};

sub get_syscmd_lock_for_cmd ( $self, $args ) {

    return unless defined $self->{syscmd_binary};

    if ( $self->{syscmd_binary} =~ m{/(apt|apt-get|apt-cache)$} ) {
        my $binary       = $1;
        my $cpbinary_for = {
            'apt'       => 'Cpanel::Binaries::Debian::Apt',
            'apt-get'   => 'Cpanel::Binaries::Debian::AptGet',
            'apt-cache' => 'Cpanel::Binaries::Debian::AptCache',
        };

        return $cpbinary_for->{$binary}->new->get_lock_for_cmd( $self->logger, $args );
    }

    die qq[Unknown binary: $self->{syscmd_binary}];
}

sub list ( $self, $type = "all", $prefix = undef ) {
    $prefix .= "*" if length($prefix) && index( $prefix, "*" ) == -1;

    my @pkgs;
    my $success = 0;
    if ( $type eq "installed" && -x "/usr/bin/dpkg-query" ) {

        # ZC-11669: This is a specific performance improvement, dpkg-query only deals
        # with installed packages

        # these ENV changes are copied from Cpanel::PackMan::Sys::syscmd

        local $ENV{LANG}        = "C";    # isn't local() via before_exec => sub { $ENV{LANG} = "C" },
        local $ENV{LANGUAGE}    = "C";
        local $ENV{LC_ALL}      = "C";
        local $ENV{LC_MESSAGES} = "C";
        local $ENV{LC_CTYPE}    = "C";

        my $run = Cpanel::SafeRun::Object->new(
            'program' => '/usr/bin/dpkg-query',
            'args'    => [ '--showformat', "\${Package}\n", '--show' ],
            timeout   => 60,
        );

        if ( !$run->CHILD_ERROR() ) {
            my @pkgs_installed = split( /\n/, $run->stdout() );
            @pkgs    = length($prefix) ? Text::Glob::match_glob( $prefix, @pkgs_installed ) : @pkgs_installed;
            $success = 1;

            # we could return here, but this list is longer than the
            # properly filtered list (see below) so we will allow this to
            # be further filtered.
        }
    }

    if ( $success == 0 ) {
        @pkgs = length($prefix) ? Text::Glob::match_glob( $prefix, @{ $self->_all_pkgs } ) : @{ $self->_all_pkgs };
    }

    my $pkgs_state = $self->_ask_apt_api_for_pkg_state_hr(@pkgs);

    # exists $_->{state} is false on virtual_packages
    if ( $type eq "all" ) {
        return [ sort keys %{$pkgs_state} ];
    }
    elsif ( $type eq "available" ) {
        return [ grep { $pkgs_state->{$_} eq "not_installed" } sort keys %{$pkgs_state} ];
    }
    elsif ( $type eq "updates" ) {
        return [ grep { $pkgs_state->{$_} eq "updatable" } sort keys %{$pkgs_state} ];
    }
    elsif ( $type eq "installed" ) {
        return [ grep { $pkgs_state->{$_} eq "installed" || $pkgs_state->{$_} eq "updatable" } sort keys %{$pkgs_state} ];
    }
    else {
        die "Unknown type “$type” passed to sys->list\n";
    }

    return;    #noop
}

sub clean ($self) {
    return $self->syscmd( sub { return $_[0] }, "clean" );
}

sub cache ($self) {

    # syscmd() dies on failure
    $self->syscmd( sub { return $_[0] }, "update" );    # resynchronize the package index files

    # no good way to local() an attribute so here is a gross hack
    local $self->{syscmd_binary} = '/usr/bin/apt-cache';
    $self->syscmd( sub { return $_[0] }, "gencaches" );    # creates APT's package cache

    return 1;
}

sub _expand_pkgs_to_args (@pkgs) {
    my $opts = ref( $pkgs[-1] ) ? pop(@pkgs) : {};

    my @args;

    for my $pkg (@pkgs) {

        # Turn URLs into local files.
        if ( $pkg =~ m{^(?:https?|ftp)://} ) {    # Cpanel::Validate::URL::is_valid_url() will match package names so can’t use that
            require Cpanel::HTTP;
            my $tmp = Cpanel::HTTP::download_to_file($pkg);
            rename $tmp, "$tmp.deb";
            push @args, "$tmp.deb";
            next;
        }
        push @args, $pkg;
    }

    if ( exists $opts->{only_from_repos} ) {
        die "`only_from_repos` given but it is not an array ref\n" if ref( $opts->{only_from_repos} ) ne 'ARRAY';
        die "`only_from_repos` given but it is empty\n"            if @{ $opts->{only_from_repos} } == 0;

        # TODO: implement $opts->{only_from_repos} ZC-9489
    }

    return @args;
}

sub install ( $self, @pkgs ) {
    my @args = _expand_pkgs_to_args(@pkgs);
    return $self->syscmd( sub { return $_[0] }, "install", "--purge", "-y", @args );
}

sub upgrade ( $self, @pkgs ) {
    my @args = _expand_pkgs_to_args(@pkgs);
    return $self->syscmd( sub { return $_[0] }, "upgrade", "--purge", "-y", @args );
}

sub uninstall ( $self, @pkgs ) {
    return $self->syscmd( sub { return $_[0] }, "purge", "-y", @pkgs );
}

sub is_unavailable ($self) {

    # the exit value is what indicates availability, usually there is no output to even check
    `fuser /var/lib/dpkg/lock >/dev/null 2>&1`;    ## no critic qw(ProhibitQxAndBackticks)
    return 1 if $? == 0;
    return 0;
}

sub parse_lines_for_errors ( $self, $lines_ar ) {
    my @errors;

    for my $line ( @{$lines_ar} ) {
        chomp $line;    # probably already done but juuuust in case
        if ( $line =~ m/^E:\s+(.*)/ ) {
            push @errors, "$1";    # copy since $1 can have unexpected side effects
        }
    }

    return @errors;
}

sub info ( $self, $pkg ) {
    my ($hr) = @{ $self->_ask_apt_perl_api_for_pkg_info($pkg) };
    return if !$hr || !keys %{$hr};
    return $hr;
}

my $prefix_cache;

sub multi_info ( $self, %args ) {
    my @want;

    # $args{'disable-excludes'} is noop for apt, it will get you the info regardless of if its on hold or not
    # $args{'populate-provides'} is noop for apt, it always does provided
    push @want, @{ $args{packages} } if $args{packages};
    if ( $args{prefixes} ) {
        for my $prefix ( @{ $args{prefixes} } ) {
            $prefix .= "*" if index( $prefix, "*" ) == -1;

            if ( !exists $prefix_cache->{$prefix} ) {
                $prefix_cache->{$prefix} = [ Text::Glob::match_glob( $prefix, @{ $self->_all_pkgs } ) ];
            }

            push @want, @{ $prefix_cache->{$prefix} };
        }

        @want = Cpanel::ArrayFunc::Uniq::uniq(@want);
    }

    die "No `packages` or `prefixes` given\n" if !@want;

    my @pkgs = @{ $self->_ask_apt_perl_api_for_pkg_info(@want) };
    return if !@pkgs;
    return \@pkgs;
}

has _all_pkgs => (
    is      => "lazy",
    default => sub ($self) {
        return $self->jsoncmd("all_pkgs");
    },
);

sub _ask_apt_api_for_pkg_state_hr ( $self, @pkgs ) {

    # The @pkgs array can contain up to 70k elements
    # when we are attempting to list all installed
    # packages on the system.
    # This is called when installing an EA4 profile
    my %aggregate_res;
    while ( my @chunk = splice @pkgs, 0, 2048 ) {
        %aggregate_res = (
            %aggregate_res,
            %{ $self->jsoncmd( pkg_state_hr => @chunk ) }
        );
    }

    return \%aggregate_res;
}

sub _ask_apt_perl_api_for_pkg_info ( $self, @pkgs ) {

    # The @pkgs array can contain up to 70k elements
    # when we are attempting to list all installed
    # packages on the system.
    # This is called when installing an EA4 profile
    my @aggregate_res;
    while ( my @chunk = splice @pkgs, 0, 2048 ) {
        push @aggregate_res, @{ $self->jsoncmd( pkg_info => @chunk ) };
    }

    return \@aggregate_res;
}

sub normalize_pkg_hr ( $self, $raw_hr ) {
    die            if ref($raw_hr) ne 'HASH';
    return $raw_hr if $raw_hr->{is_virtual};

    my $pkg = $raw_hr->{Package};
    $raw_hr->{Description} //= $raw_hr->{"Description-en"} || "$pkg (no description)";

    # There is no corresponding field for debs,
    #   debify makes the SPEC’s summary
    #   the first line of the description
    if ( !exists $raw_hr->{Summary} ) {    # just in case it ever gets added
        my @desc = split( /\n/, $raw_hr->{Description} );
        $raw_hr->{Summary}     = shift @desc;
        $raw_hr->{Description} = join( "\n", @desc );
    }

    $raw_hr->{Description} =~ s/^\s+//;

    $raw_hr->{"APT-Sources"} //= "Unknown";
    my $license = "Unknown";
    if ( open my $fh, "<", "/usr/share/doc/$pkg/copyright" ) {
        while ( my $line = <$fh> ) {

            # regarding “License” content:
            #    the “first line is an abbreviated name for the license, or expression giving alternatives”
            if ( $line =~ m/^License:\s+(.*)/ ) {
                $license = $1;
                last;
            }
        }
    }

    my $res_hr = {
        package           => $raw_hr->{Package},
        architecture      => $raw_hr->{Architecture},
        size              => $raw_hr->{Size},
        release           => "N/A",                     # See ZC-8761
        version           => $raw_hr->{Version},
        short_description => $raw_hr->{Summary},
        long_description  => $raw_hr->{Description},
        more_info_url     => $raw_hr->{Homepage},
        license           => $license,
        pkg_dep_raw       => {
            requires  => $raw_hr->{Depends},
            conflicts => $raw_hr->{Conflicts},
        },
        pkg_dep => {
            requires  => [ Cpanel::ArrayFunc::Uniq::uniq( @{ $raw_hr->{Depends_with_virtual_packages_expanded}   // [] } ) ],
            conflicts => [ Cpanel::ArrayFunc::Uniq::uniq( @{ $raw_hr->{Conflicts_with_virtual_packages_expanded} // [] } ) ],
        },
        repo_name => $raw_hr->{"APT-Sources"},
        vendor    => $raw_hr->{Maintainer},
        pkg_group => $raw_hr->{Section},         # See ZC-8770

        version_latest    => $raw_hr->{version_latest},
        version_installed => ( $raw_hr->{version_installed} // "" ),
        state             => $raw_hr->{state},
    };

    if ( $ENV{PACKMAN_DEBUG} ) {
        $res_hr->{debian_index_file} = $raw_hr->{debian_index_file};
    }
    else {
        delete $res_hr->{pkg_dep_raw};
    }

    return $res_hr;
}

my %yumtxnsymbol = (
    upgrade   => "+",
    update    => "+",
    install   => "+",
    uninstall => "-",
);

sub _aptify_txn_file ( $self, $file ) {
    my @pkg_args;

    require Path::Tiny;
    my $po = Path::Tiny::path($file);
    for my $line ( Path::Tiny::path($file)->lines ) {
        chomp $line;
        next if !$line;

        my ( $act, @pkgs ) = split " ", $line;
        for my $pkg (@pkgs) {
            next if !exists $yumtxnsymbol{$act};    # e.g. …/490_mod_bwlimited.conf 0fd3a850dc999897c3ccae67d7cd082b

            # apt’s virtual package behavior is weird
            #    * If a virtual package is provided by more than one thing (i.e. the point of virtual packages) then apt barfs wanting you to pick one.
            #    * There is no mechanism to configure it to not barf and instead choose the first one if its not installed
            #    * It still barfs even if you have them installed
            #    * doing `pkg-real | pkg2-real | pkg-virt` type deps do not give it the hint it needs
            # So we do it here :( unfortunately
            my ($pko) = @{ $self->_ask_apt_perl_api_for_pkg_info($pkg) };
            if ( $pko->{is_virtual} ) {
                my $have_installed = 0;
                my @providers      = @{ $self->_ask_apt_perl_api_for_pkg_info( @{ $pko->{provided_by} } ) };

                for my $pm ( map { $_->{version_installed} ? ($_) : () } @providers ) {
                    if ( $pm->{version_installed} ) {

                        # dupes welcome, apt does the right thing should that happen
                        push @pkg_args, "$pm->{Package}$yumtxnsymbol{$act}";
                        $have_installed++;
                    }
                }

                if ( !$have_installed ) {    # if they don’t already have one use the first one

                    # dupes welcome, apt does the right thing should that happen
                    push @pkg_args, "$pko->{provided_by}[0]$yumtxnsymbol{$act}";
                }
            }
            else {
                # dupes welcome, apt does the right thing should that happen
                push @pkg_args, "$pkg$yumtxnsymbol{$act}";
            }
        }
    }

    return @pkg_args;
}

sub syscmd_args_txn ( $self, $file ) {
    my @args = $self->_aptify_txn_file($file);
    return ( qw(autoremove --purge), @args );
}

sub syscmd_args_txn_dryrun ( $self, $file ) {
    my @args = $self->_aptify_txn_file($file);
    return ( qw(autoremove --purge --simulate), @args );
}

sub parse_syscmd_txn_output ( $self, $lines_ar, $trans_data ) {
    my $state  = 'unknown';
    my @errors = $self->parse_lines_for_errors($lines_ar);
    return @errors if @errors;

    foreach my $line ( @{$lines_ar} ) {
        if ( $line =~ m/^(\S+)\s+is already the newest version/ ) {
            $trans_data->{unaffected}{$1} = 1;
            next;
        }
        elsif ( $line =~ m/^The following additional packages will be installed:/ ) {
            $state = "install";
            next;
        }
        elsif ( $line =~ m/^The following packages will be REMOVED:/ ) {
            $state = "uninstall";
            next;
        }
        elsif ( $line =~ m/^The following NEW packages will be installed:/ ) {
            $state = "install";
            next;
        }
        elsif ( $line =~ m/^The following packages will be upgraded:/ ) {
            $state = "upgrade";
            next;
        }
        else {
            last if $line =~ m/^\d+ upgraded, \d+ newly installed, \d+ to remove and \d+ not upgraded/;
            next if $state eq 'unknown';

            if ( $line =~ m/^  (\S.*)$/ ) {
                my $pkgs = $1;
                for my $pkg ( split( /\s+/, $pkgs ) ) {

                    # the * apt adds causes confusion like ZC-9226
                    $pkg =~ s/\*$//;

                    $trans_data->{$state}{$pkg}++;
                }
            }
            else {
                $state = 'unknown';
                next;
            }
        }
    }

    return @errors;    # will always be empty at this point unless the code above is modified, so just in case ¯\_(ツ)_/¯
}

sub syscmd_line_indicates_headers_are_done ( $self, $line ) {
    return 2;          # we use --quiet to squelsh “headers”
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::PackMan::Sys::apt - Implements apt support for Cpanel::PackMan

=head1 VERSION

This document describes Cpanel::PackMan::Sys::apt version 0.01

=head1 SYNOPSIS

Do not use directly. Instead use L<Cpanel::PackMan>.

=head1 DESCRIPTION

Subclass of L<Cpanel::PackMan::Sys> implementing C<apt> support for PackMan.
