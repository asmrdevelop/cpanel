package Cpanel::PluginManager;

# cpanel - Cpanel/PluginManager.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use warnings;
use strict;

sub new {
    my ( $class, %opts ) = @_;

    die "No directory list supplied.\n" unless exists $opts{'directories'} and 'ARRAY' eq ref $opts{'directories'} and scalar @{ $opts{'directories'} };
    die "No namespace supplied.\n" unless exists $opts{'namespace'} and $opts{'namespace'};
    die "Namespace '$opts{'namespace'}' not a valid Perl namespace.\n"
      unless $opts{'namespace'} =~ m{^ \w+ (?: :: \w+ )* $}x;

    # This is a little laxer than I would like but necessary until /var/cpanel/perl5/lib is
    # guaranteed to exist and be in @INC.
    my %incdirs = map  { $_ => undef } @INC;
    my @dir     = grep { -d $_ && exists $incdirs{$_} } @{ $opts{'directories'} };

    die "None of the directories supplied are directories and in \@INC\n" unless @dir;

    my $self = {
        'directories' => \@dir,
        'namespace'   => $opts{'namespace'},
        'plugins'     => {},
    };

    return bless $self, $class;
}

sub list_plugin_names {
    my ($self) = @_;

    if ( scalar keys %{ $self->{'plugins'} } ) {
        my @sorted_list = sort keys %{ $self->{'plugins'} };
        return @sorted_list;
    }

    my @plugin_names;
    my $ns = $self->{'namespace'};
    $ns =~ s{::}{/}g;
    foreach my $dir ( @{ $self->{'directories'} } ) {
        my $pdir = "$dir/$ns";
        opendir( my $dh, $pdir ) or next;
        foreach my $file ( grep { !/^\.\.?/ } readdir $dh ) {
            next unless -f "$pdir/$file";
            push @plugin_names, $1 if $file =~ m/^(\w+)\.pm$/;
        }
        closedir $dh;
    }

    my @sorted_plugin_names = sort @plugin_names;
    return @sorted_plugin_names;
}

sub load_all_plugins {
    my ($self) = @_;

    foreach my $dir ( @{ $self->{'directories'} } ) {
        $self->load_plugins($dir);
    }
    return;
}

sub load_plugins {
    my ( $self, $root_dir ) = @_;

    die "No directory supplied for finding plugins.\n"     unless defined $root_dir and length $root_dir;
    die "Supplied directory '$root_dir' does not exist.\n" unless -d $root_dir;

    # TODO : Re-enable after coordinating with ToddR on getting /var/cpanel/perl5/lib to @INC
    #    die "Supplied directory '$root_dir' not part of Perl's include path.\n" unless grep { $_ eq $root_dir } @INC;

    my $ns_dir = join( '/', $root_dir, split( '::', $self->{'namespace'} ) );

    # not having the namespace in that root is not an error.
    return unless -d $ns_dir;

    opendir( my $dir, $ns_dir ) or die "Unable to read directory '$ns_dir': $!\n";
    my @files = grep { !/^\.\.?$/ } readdir($dir);
    closedir($dir) or die "Failed to close directory '$ns_dir': $!\n";

    # TODO: Do we want to handle subdirectories?
    my @modules = map { ( /^(\w+)\.pm$/ and -f "$ns_dir/$_" ) ? $1 : () } @files;
    foreach my $mod (@modules) {
        eval { $self->load_plugin_by_name($mod) };
        if ( my $exception = $@ ) {
            print STDERR "Dynamic module failed to load module '$mod' with: $exception";
        }
    }

    return unless defined wantarray;

    return $self->get_loaded_plugins;
}

sub reset_plugin_list {
    my ($self) = @_;
    $self->{'plugins'} = {};
    return;
}

sub load_plugin_by_name {
    my ( $self, $modname ) = @_;

    # Don't try to reload.
    return if exists $self->{'plugins'}->{$modname};

    my $fullmodname = $self->{'namespace'} . '::' . $modname;
    eval "require $fullmodname;";
    if ($@) {
        warn "Failed to load '$fullmodname' plugin: $@\n";
        return;
    }

    return $self->{'plugins'}->{$modname} = $fullmodname->new();
}

sub get_loaded_plugins {
    my ($self) = @_;

    my @sorted_plugins = sort { $a->priority <=> $b->priority || $a->name cmp $b->name } values %{ $self->{'plugins'} };
    return @sorted_plugins;
}

1;
