package Cpanel::ModuleDeps;

# cpanel - Cpanel/ModuleDeps.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use warnings;
use strict;
use Carp;

use Module::Want ();
use IO::Handle   ();
use IPC::Open3   ();

my $tsort_bin = '/usr/bin/tsort';

my %filter = (
    'use'     => qr/^use$/,
    'modules' => qr/^(?:use|require)$/,
    'all'     => qr/^\w/,
);

sub new {
    my ( $class, %args ) = @_;

    if ( exists $args{'incdir'} ) {
        $args{'incdir'} = [ $args{'incdir'} ] unless ref $args{'incdir'};
        die "'incdir' parameter must be either a single directory or a reference to an array of directories."
          if 'ARRAY' ne ref $args{'incdir'};
        foreach my $dir ( @{ $args{'incdir'} } ) {
            die "'incdir' list contains '$dir' which is not a valid directory." unless -d $dir;
        }
    }

    if ( exists $args{'excludes'} ) {
        $args{'exclude'} = [ $args{'exclude'} ] unless ref $args{'exclude'};
        die "'exclude' parameter must be either a single module name or a reference to an array of module names."
          if 'ARRAY' ne ref $args{'exclude'};
    }

    if ( exists $args{'basedir'} ) {
        die "'basedir' parameter is not a valid directory." unless -d $args{'basedir'};
    }
    else {
        $args{'basedir'} = '.';
    }

    if ( exists $args{'filter'} and !exists $filter{ $args{'filter'} } ) {
        die "'filter' parameter has invalid value, supported values are ", join( ', ', sort keys %filter );
    }

    die "Not allowed to execute $tsort_bin\n" if $args{'sorted'} && !-x $tsort_bin;
    my $self = bless {
        sorted   => $args{'sorted'} ? 1 : 0,
        filter   => $args{'filter'} || 'modules',
        base_dir => $args{'basedir'},
        deps     => {},
        exclude  => { map { $_ => 1 } @{ $args{'exclude'} || [] } },
        incdir   => [ @{ $args{'incdir'} || [] } ],
      },
      $class;

    return $self;
}

sub build_dependency_tree {
    my $self = shift;

    my $regex = $filter{ $self->{'filter'} };

    my $target;
    while (@_) {
        $target = shift;
        next if $self->{'exclude'}->{$target};

        # Don't parse if target is already processed.
        next if exists $self->{'deps'}->{$target};

        my $file = _is_perl_file($target) ? $target : _file_from_module( $self->{'base_dir'}, $target );
        my @deps = grep { $_->[0] =~ $regex && $_->[1] ne $target } $self->list_module_inclusions($file);

        $self->{'deps'}->{$target} = \@deps;

        # Recurse over all of my dependencies
        $self->build_dependency_tree( map { $_->[0] =~ /^ns_/ ? () : $_->[1] } @deps );
    }
    return;
}

sub build_script_dependency_tree {
    my $self = shift;

    my $regex = $filter{ $self->{'filter'} };

    my $target;
    while (@_) {
        $target = shift;
        next unless $target;
        next if $self->{'exclude'}->{$target};

        # Don't parse if target is already processed.
        next if exists $self->{'deps'}->{$target};

        my $file = $target;
        if ( -e $file && _is_perl_file( $file, symlink_ok => 1 ) ) {
            1;
        }
        elsif ( $target =~ m{^(.*)\.static$} ) {
            my $nonstatic = $1;
            if ( -f $nonstatic && _is_perl_file($nonstatic) ) {
                $file = $nonstatic;
            }
        }
        elsif ( ( !-f $target || !_is_perl_file($target) ) && -f "$target.pl" ) {

            $file = "$target.pl";
        }
        else {
            $file = _file_from_module( $self->{'base_dir'}, $target ) or die("_file_from_module( $self->{'base_dir'}, $target )");
        }

        my @deps = grep { $_->[0] =~ $regex && $_->[1] ne $target } $self->list_module_inclusions($file);

        # Make sure to add dependency for source file to target dir
        $self->{'deps'}->{$target} = [ [ 'use', $file ] ] unless $target eq $file;
        $self->{'deps'}->{$file}   = \@deps;

        # Recurse over all of my dependencies
        $self->build_dependency_tree( map { $_->[0] =~ /^ns_/ ? () : $_->[1] } @deps );
    }
    return;
}

# Return a list of all of the dependencies by recursing through the list of dependencies
# starting with $target. Only return local modules and perl scripts.
sub list_dependencies {
    my ( $self, $target ) = @_;

    if ( $self->{'sorted'} ) {
        return grep { $self->_is_local_module($_) || _is_perl_file($_) } $self->sorted_dependencies($target);
    }
    else {
        return grep { $self->_is_local_module($_) || _is_perl_file($_) } $self->unsorted_dependencies($target);
    }
}

sub unsorted_dependencies {
    my ( $self, $target, $seen ) = @_;

    $seen = {} unless $seen;
    my @deps;
    foreach my $dep ( map { $_->[0] !~ /^ns_/ ? $_->[1] : () } @{ $self->{'deps'}->{$target} } ) {
        next if exists $seen->{$dep};
        $seen->{$dep} = 1;
        push @deps, $self->unsorted_dependencies( $dep, $seen );
        push @deps, $dep;
    }
    return @deps;
}

sub sorted_dependencies {
    my ( $self, $target ) = @_;

    my $read  = IO::Handle->new();
    my $write = IO::Handle->new();
    my $err   = IO::Handle->new();
    my $pid   = IPC::Open3::open3( $write, $read, $err, $tsort_bin );

    _write_dep_pairs( $write, $target, $self->{'deps'}, {} );
    close $write;
    my @deps = <$read>;
    chomp @deps;
    close $read;
    waitpid( $pid, 0 );
    if ($?) {
        warn "unexpected errors from $tsort_bin";
        while ( my $line = <$err> ) {
            warn $line;
        }
        die( "Unexpected exit code from $tsort_bin: " . ( $? >> 8 ) );
    }

    # Remove $target from dependency list
    shift @deps;
    return reverse @deps;
}

sub _write_dep_pairs {
    my ( $fh, $target, $deps, $seen ) = @_;

    # Make certain we don't circle or reprint stuff we've already done
    return if exists $seen->{$target};
    $seen->{$target} = 1;

    foreach my $dep ( @{ $deps->{$target} } ) {
        print {$fh} "$target $dep->[1]\n" if $dep->[0] !~ /^ns_/;
        _write_dep_pairs( $fh, $dep->[1], $deps, $seen );
    }
    return;
}

sub list_plugin_dirs {
    my ( $self, $target, $seen ) = @_;

    $seen = {} unless $seen;
    my @deps;
    foreach my $dep ( @{ $self->{'deps'}->{$target} } ) {
        my $ns = $dep->[1];
        next if exists $seen->{$ns};
        $seen->{$ns} = 1;
        if ( $dep->[0] =~ /^ns_/ ) {
            $ns =~ s/::$//;
            push @deps, $ns;
        }
        else {
            push @deps, $self->list_plugin_dirs( $ns, $seen );
        }
    }

    return @deps;
}

sub _is_local_module {
    my ( $self, $module ) = @_;
    return unless defined $module;
    foreach my $dir ( '.', @{ $self->{'incdir'} } ) {
        return 1 if _file_from_module( $dir, $module );
    }
    return;
}

# Returns true if the suppled file is a Perl script file
sub _is_perl_file {
    my ( $file, %opts ) = @_;

    # ignore binary files
    return   if -B $file;
    return   if -l $file && !$opts{symlink_ok};
    return 1 if $file =~ /\.(?:pl|cgi)$/;

    open my $fh, '<', $file or return;
    my $shbang = <$fh>;
    return 1 if ( $shbang =~ /perl/ );

    # Isn't a shell script either
    return 0 unless ( $shbang =~ m/^#!.*sh\b/ );

    # Support dual sh/perl scripts
    while ( my $line = <$fh> ) {
        return 1 if ( $line =~ m/perl\s+-x\b/ );
    }
    return 0;
}

# Create the appropriate relative file name from the supplied module name.
# We'll also discard modules that are not part of the cPanel/WHM install
# (through the use of the file check).
sub _file_from_module {
    my ( $base_dir, $mod ) = @_;
    my $file = Module::Want::get_inc_key($mod);
    if ( !defined $file ) {
        return $mod if $mod =~ qr{\.pm$};
        return;
    }

    #    die "'$mod' generated an undefined file name." unless defined $file;
    return unless -f "$base_dir/$file";
    return $file;
}

# Extract the 'use'd modules from the supplied file. Uses a simple regex check.
sub _list_module_inclusions {
    my ( $self, $seen, $file, $use_only ) = @_;

    return unless defined $file;
    open my $fh, '<', "$self->{'base_dir'}/$file" or do {
        Carp::cluck("Unable to find/read '$file': $!\n");
        return;
    };
    my @deps;
    my $in_use_base = 0;
    my $in_pod      = 0;
    my $verbose     = 0;
    my $regex       = $use_only ? qr/^\s*(use)\s+(?:qw\()?([A-Z][\w:]+)(?:\))?/ : qr/^\s*(require|use)\s+(?:qw\()?([A-Z][\w:]+)(?:\))?/;
    while ( my $line = <$fh> ) {
        last if index( $line, '__END__' ) == 0 || index( $line, '__DATA__' ) == 0;
        next if $line =~ m/#\s*Hide Depend/;                                         # The code has declared this line is not to be detected as a dependency.

        # Strip POD
        if ( index( $line, '=' ) == 0 ) {
            if ( index( $line, '=cut' ) == 0 ) {
                $in_pod = 0;
                next;
            }
            elsif ( $line =~ m{^=(\w+)} ) {
                print "  Skipping POD =$1\n" if ($verbose);
                $in_pod = 1;
            }

        }
        next if ($in_pod);

        if ( $in_use_base || $line =~ m{^\s*use\s+(?:base|parent)\s+(?:qw\(|["'])?(.+)} ) {
            my $modules = $in_use_base ? $line : $1;
            $modules =~ s/\n//g;
            $modules =~ s/#.*?$//;
            $modules =~ s/\s*;\s*$//;

            $in_use_base = 1;
            $in_use_base = 0 if ( $modules =~ s{['"\)]}{}g );

            foreach my $module ( split( m{\s+}, $modules ) ) {
                next if !$module || !Module::Want::is_ns($module) || $self->{'exclude'}->{$module};
                push @deps, [ 'use', $module ];
            }
        }

        # By not using a namespace-specific regex, I can find other cases. Like new plugin directories.
        elsif ( my ( $type, $mod ) = $line =~ $regex ) {
            next if $self->{'exclude'}->{$mod};
            if ( Module::Want::is_ns($mod) ) {
                push @deps, [ $type, $mod ];
                next;
            }

            # Special code for dealing with plugins or runtime loaded modules
            next unless $mod =~ /::$/;
            push @deps, [ "ns_$type", $mod ];
        }
    }
    close $fh;

    # exception for Cpanel::Exception, include Cpanel::Exception::CORE instead of Cpanel::Exception
    @deps = map { $_->[1] eq 'Cpanel::Exception' ? [ $_->[0], 'Cpanel::Exception::CORE' ] : $_ } @deps;

    return @deps;
}

sub list_module_inclusions {
    my ( $self, $file ) = @_;
    my @mods = $self->_list_module_inclusions( {}, $file );
    return @mods;
}

1;
