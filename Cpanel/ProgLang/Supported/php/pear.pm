package Cpanel::ProgLang::Supported::php::pear;

# cpanel - Cpanel/ProgLang/Supported/php/pear.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use Cpanel::Exception       ();
use Cpanel::ForkAsync       ();
use Cpanel::SafeRun::Object ();

sub get_relative_binary_path  { return '/usr/bin/pear'; }
sub get_display_name_singular { return 'PHP Extensions and Applications Package'; }    # corresponds to the 'name' key in Cpanel::LangMods
sub get_display_name_plural   { return 'PHP Extension(s) and Application(s)'; }        #corresponds to the 'names' key in Cpanel::LangMods
sub get_php_dir_arguments     { return [ 'config-get', 'php_dir' ]; }
sub search_blocks_beta        { return 1; }

sub new {
    my ( $class, $opts_hr ) = @_;

    if ( !( $opts_hr && 'HASH' eq ref $opts_hr ) ) {
        die Cpanel::Exception::create( 'MissingParameter', 'You must provide a [asis,hashref] with [list_and_quoted,_1] keys', [ [ 'lang', 'package' ] ] );    ## no extract maketext (developer error message. no need to translate)
    }
    _validate_required_params($opts_hr);

    return bless(
        {
            'lang'    => $opts_hr->{'lang'},
            'type'    => ( split /::/, $class )[-1],
            'package' => $opts_hr->{'lang'}->get_package( 'package' => $opts_hr->{'package'} ),
        },
        $class
    );
}

sub get_binary_path {
    my $self = shift;
    return $self->{'package'}->get_install_prefix() . $self->get_relative_binary_path();
}

sub get_php_dir {
    my $self = shift;

    my $result;
    try {
        $result = $self->_call_binary( { 'args' => $self->get_php_dir_arguments(), 'fatal' => 1 } );
    }
    catch {
        require Cpanel::Logger;
        require Cpanel::Locale;
        Cpanel::Logger->new()->warn( Cpanel::Exception::get_string($_) );
        $result = Cpanel::Locale->get_handle()->maketext('Path not found.');
    };

    return $result;
}

sub get_installed_list {
    my $self   = shift;
    my $output = $self->_call_binary( { 'args' => ['list'] } );
    return $self->_parse_list_output( \$output );
}

sub search {
    my ( $self, $search_term ) = @_;
    my $output = $self->_call_binary( { 'args' => [ 'search', $search_term ] } );
    return $self->_parse_list_output( \$output );
}

sub list_available {
    my $self   = shift;
    my $output = $self->_call_binary( { 'args' => ['list-all'] } );
    return $self->_parse_list_output( \$output );
}

sub install {
    my ( $self, $opts_hr ) = @_;
    return $self->_module_action( 'install', $opts_hr );
}

sub update {
    my ( $self, $opts_hr ) = @_;
    return $self->_module_action( 'upgrade', $opts_hr );
}

sub uninstall {
    my ( $self, $opts_hr ) = @_;
    return $self->_module_action( 'uninstall', $opts_hr );
}

sub reinstall {
    my ( $self, $opts_hr ) = @_;

    my $output = $self->_module_action( 'uninstall', $opts_hr );
    $output .= $self->_module_action( 'install', $opts_hr );
    return $output;
}

sub _module_action {
    my ( $self, $action, $opts_hr ) = @_;

    return $self->_call_binary(
        {
            'args' => [ $action, $opts_hr->{'module'} ],
            ( $opts_hr->{'output_cb'} ? ( 'output_cb' => $opts_hr->{'output_cb'} ) : () ),
        }
    );
}

sub _call_binary ( $self, $opts_hr ) {

    # ForkAsync throwing a warning will result in redundant error output
    local $Cpanel::ForkAsync::no_warn = 1;

    my $run = Cpanel::SafeRun::Object->new(
        'program'     => $self->get_binary_path(),
        'args'        => $opts_hr->{'args'},
        'before_exec' => sub {

            # PIG-1873: chdir to the SCL pear directory,
            # so that the error_log is created there.
            my $path = $self->{'package'}->get_install_prefix() . '/usr/share/pear';
            chdir $path or die Cpanel::Exception::create( 'IO::ChdirError', [ 'error' => $!, 'path' => $path ] );

            if ( $opts_hr->{'args'}->[0] eq 'install' && $self->can('is_install_allowed') ) {
                $self->is_install_allowed( $opts_hr->{'args'}->[1] );
            }

            if ( $opts_hr->{args}[0] eq "install" && $opts_hr->{args}[1] eq "imagick" ) {
                require Cpanel::SysPkgs;
                require Cpanel::OS;
                Cpanel::SysPkgs->new()->install_packages( packages => [ Cpanel::OS::package_ImageMagick_Devel() ] )
                  or die "[ERROR] Failed to ensure ImageMagick devel package for imagick PECL\n";
            }
        },
        ( $opts_hr->{'output_cb'} ? ( 'stderr' => $opts_hr->{'output_cb'}, 'stdout' => $opts_hr->{'output_cb'} ) : () ),
    );

    $run->die_if_error if $opts_hr->{'fatal'};

    if ( !$opts_hr->{'output_cb'} ) {
        my $out = $run->stdout();
        chomp $out;
        return $out;
    }

    return 1;
}

# Taken from Cpanel::LangMods - mostly as-is
sub _parse_list_output {    ## no critic(RequireArgUnpacking)
    my $self = shift;

    my $inml = 0;
    my @MODLIST;
    my ( @VLIST, @VERSIONLIST, $module, $vi, $info, $latest, $stable, $installed );
    foreach ( split( /\n/, ${ $_[0] } ) ) {
        if ($inml) {
            chomp();
            if (/^\s+/) {
                if (@MODLIST) {
                    my $extra_info = $_;
                    $extra_info =~ s/^\s+//;
                    $MODLIST[-1]->{'info'} .= " " . $extra_info;
                }
                next;
            }
            next if !( $_ && $_ !~ m{^\s*(<br />|<b>)} );

            ( $module, $vi ) = split( /\s+/, $_, 2 );
            $module =~ s{^$self->{'type'}/}{}g;

            my @parse_block = split( /(\s+)/, $vi );
            while ( @parse_block && $parse_block[0] =~ m/^[\(0-9]/ ) {
                my $version = shift(@parse_block);
                $version =~ s/[()]//g;
                if ( $version =~ m{/} ) {
                    my @VERSIONS = split( m{/}, $version );
                    push @VLIST, pop(@VERSIONS);
                    push @VLIST, join( '/', @VERSIONS ) if @VERSIONS;
                }
                else {
                    push @VLIST, $version;
                }
                shift(@parse_block) if $parse_block[0] =~ m/^\s*$/;
            }
            $info = join( '', @parse_block );
            next unless $info;
            $latest      = shift(@VLIST);
            $installed   = $stable = shift(@VLIST);
            @VERSIONLIST = ();
            if ($stable)    { push @VERSIONLIST, $stable; }
            if ($latest)    { push @VERSIONLIST, $latest; }
            if ( !$stable ) { $stable = $latest; }
            $module =~ s/^pear\///g;
            next if ( !$module || $module eq '' );
            next if ( search_blocks_beta() && $stable && ( $stable eq 'beta' || $stable eq 'alpha' ) );
            push @MODLIST, {
                'module'    => $module,
                'latest'    => $latest,
                'stable'    => $stable,
                'installed' => $installed,
                'info'      => $info,
                'docurl'    => 'http://' . $self->{'type'} . '.php.net/package/' . $module . '/',
            };
        }
        if ( !/\s+Package/i && /Package\s+/i ) {
            $inml = 1;
        }
    }
    return \@MODLIST;
}

sub _validate_required_params {
    my $opts_hr = shift;

    my $validators = {
        'lang'    => sub { return 1 if ( ref $_[0] && $_[0]->isa('Cpanel::ProgLang::Supported::php') ); return 0; },
        'package' => sub { return 1 if defined $_[0];                                                   return 0; },
    };

    my @exceptions;
    foreach my $required_arg ( keys %{$validators} ) {
        push @exceptions, Cpanel::Exception::create( 'InvalidParameter', 'The specified value for “[_1]” is invalid.', [$required_arg] )    ## no extract maketext (developer error message. no need to translate)
          if !$validators->{$required_arg}->( $opts_hr->{$required_arg} );
    }

    die Cpanel::Exception::create( 'Collection', 'Invalid or Missing required parameters', [], { exceptions => \@exceptions } ) if scalar @exceptions;
    return 1;
}

1;
