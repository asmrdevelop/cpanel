package Cpanel::Init::Utils;

# cpanel - Cpanel/Init/Utils.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule ();

# Out of the Perl Cookbook.
sub commify_series {
    return (
          ( @_ == 0 ) ? ''
        : ( @_ == 1 ) ? $_[0]
        : ( @_ == 2 ) ? join( " and ", @_ )
        :               join( ', ', @_[ 0 .. $#_ - 1 ], "and $_[-1]" )
    );
}

sub execute {
    my ( $script, @args ) = @_;
    Cpanel::LoadModule::load_perl_module('Cpanel::SafeRun::Simple');
    Cpanel::LoadModule::load_perl_module('File::Basename');

    my @cmds = ( $script, @args );
    local $? = 32512;    # failed to exec

    my $output = Cpanel::SafeRun::Simple::saferunallerrors(@cmds);

    # convert the code in an homgeneous status that could be used by Cpanel::Init::Base
    if ( !defined $? || ( $? >> 8 ) == 127 ) {
        return { 'status' => 0, 'message' => 'Command failed' };
    }
    my $status   = $? != 0 ? 0 : 1;
    my $basename = File::Basename::basename($script);
    for ($output) {
        s/\n/ /g;
        s/^\s+//;
        s/\s{2,}/ /g;
        s/$basename//;
    }
    if ( !$output ) {
        $output = join( ' ', @cmds );
    }
    return { 'status' => $status, 'message' => sprintf( "[%s] %s\n", $basename, $output ) };
}

sub load_subclass {
    my ($package) = @_;

    my $file = $package . '.pm';
    $file =~ s{::}{/}g;

    eval { CORE::require($file) };
    if ($@) {
        my $err = $@;
        Cpanel::LoadModule::load_perl_module('Cpanel::Carp');
        die Cpanel::Carp::safe_longmess( 'Cannot require ' . $package . ': ' . $@ );
    }
    return 1;
}

sub fetch_services {
    my ($file) = @_;
    return if !-e $file;
    Cpanel::LoadModule::load_perl_module('Cpanel::CachedDataStore');
    return Cpanel::CachedDataStore::fetch_ref($file);
}

sub write_services {
    my ($services) = @_;
    my $file = '/var/cpanel/cpservices.yaml';

    Cpanel::LoadModule::load_perl_module('Cpanel::CachedDataStore');
    return Cpanel::CachedDataStore::store_ref( $file, $services );
}

sub merge_services {
    my $local = fetch_services('/var/cpanel/cpservices.yaml');
    my $new   = fetch_services('/usr/local/cpanel/etc/init/scripts/cpservices.yaml');

    if ($local) {
        Cpanel::LoadModule::load_perl_module('Cpanel::CPAN::Hash::Merge');
        return Cpanel::CPAN::Hash::Merge::merge( $local, $new );
    }
    else {
        return $new;
    }
}

sub check_services_yaml {
    my ($data) = @_;
    my @no_service;
    my %resursive_dep;
    foreach my $key ( keys %{$data} ) {
        foreach my $dep ( @{ $data->{$key} } ) {
            push @no_service, $dep if ( !exists $data->{$dep} );
            my %temp = _find_cir( $data, $dep, $key );
            foreach my $tempkey ( keys %temp ) {
                my $reverse = $temp{$tempkey};
                next if ( exists $resursive_dep{$reverse} and ( $resursive_dep{$reverse} eq $tempkey ) );
                $resursive_dep{$tempkey} = $temp{$tempkey};
            }
        }
    }

    return {
        no_service    => \@no_service,
        resursive_dep => \%resursive_dep,
      }
      if @no_service
      or %resursive_dep;
}

sub _find_cir {
    my ( $data, $dep, $watch ) = @_;
    my %stash = ();
    foreach my $key ( @{ $data->{$dep} } ) {
        if ( $key eq $watch ) {
            $stash{$watch} = $dep;
        }
    }
    return %stash;
}

1;
