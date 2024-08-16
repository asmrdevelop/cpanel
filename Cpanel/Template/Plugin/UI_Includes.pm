package Cpanel::Template::Plugin::UI_Includes;

# cpanel - Cpanel/Template/Plugin/UI_Includes.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Template::Plugin';

use Cpanel::Themes::UI_Includes ();
use Cpanel::Debug               ();
use Cpanel::Template            ();

=head1 NAME

Cpanel::Template::Plugin::UI_Includes - Provides users the ability to include templates from a custom INCLUDE_PATH.

=head1 SYNOPSIS

    # If you want to include template files from the "default" include directories (see L<Cpanel::Themes::Fallback::get_paths()>)
    # you can simple invoke the plugin as so:
    [% USE UI_Includes %]
    [% IF UI_Includes.can_load_template( 'template_file_to_load.tmpl' ) -%]
        <div>[% UI_Includes.load_template('template_file_to_load.tmpl') %]</div>
    [% END -%]

    # Alternatively, if you want to load templates from a different location that you specify, then you can invoke it with the following params:
    [% USE UI_Includes( { 'include_paths' => \@paths_to_include } ) %]
    [% IF UI_Includes.can_load_template( 'template_file_to_load.tmpl' ) -%]
        <div>[% UI_Includes.load_template('template_file_to_load.tmpl') %]</div>
    [% END -%]

=head1 METHODS

=over 8

=item B<load>

This method is called by the Template Toolkit when the plugin module is first loaded.

It initializes the singleton that will be returned on subsequent calls to L<new>.

Also see L<http://template-toolkit.org/docs/modules/Template/Plugin.html#method_load>

=cut

sub load {
    my ($class) = @_;

    my $ui_includes = Cpanel::Themes::UI_Includes->new(
        {
            'username' => $Cpanel::user,
            'owner'    => $Cpanel::CPDATA{'OWNER'} || 'root',
            'theme'    => $Cpanel::CPDATA{'RS'},
        }
    );

    my $plugin = {
        'ui_includes' => $ui_includes,
    };

    return bless $plugin, $class;
}

=item B<new>

This method is called to instantiate a new plugin object for the USE directive.

It returns the singleton initiated in L<load>.

B<Args>:

One optional argument: a hashref containing

    { 'include_paths' => \@paths_to_include }

If this is provided, then it'll update the paths configured in the C<Cpanel::Themes::UI_Includes> object as needed.

Also see L<http://template-toolkit.org/docs/modules/Template/Plugin.html#method_new>

=cut

sub new {
    my ( $self, $context, @args ) = @_;
    my $params = ref $args[-1] eq 'HASH' ? pop @args : {};

    if ( defined $params->{'include_paths'} and ref $params->{'include_paths'} eq 'ARRAY' ) {
        $self->{'ui_includes'}->set_include_paths( $params->{'include_paths'} );
    }

    return $self;
}

=item B<can_load_template>

Returns the first path where the specified template file was found.

Should be used as a check to see if the template is present or not, in order to generate the proper <div>s etc.

B<Args>:

One required argument: the filename of the template to check.

=cut

sub can_load_template {

    # my ( $self, $template_file ) = @_;
    return $_[0]->{'ui_includes'}->path_for_file( $_[1] );
}

=item B<load_template>

Returns the processed output from the template file.

Returns undef if the template is not present in the configured include_paths, or if there was an error processing the template.

B<Args>:

One required argument: the filename of the template to load.

=cut

sub load_template {
    my ( $self, $template_file, $data ) = @_;
    $data //= {};

    my $include_paths = $self->{'ui_includes'}->path_for_file($template_file) or return;

    my ( $success, $output ) = Cpanel::Template::process_template(
        'cpanel_injected',
        {
            'print'         => 0,
            'template_file' => $template_file,
            'app'           => $template_file,
            %$data
        },
        { 'include_path' => $include_paths, }
    );

    if ( $success && ref $output eq 'SCALAR' ) {

        # problems?
        return $$output;
    }

    #TODO: explore what scenarios this happens in and what the problems are with it.
    if ( !$success ) {

        # Cpanel::Template, return $Template::ERROR or $template->error on failure, so logging this for now.
        Cpanel::Debug::log_warn("Failed to process template: '$template_file' - Error: $output");
        return;
    }
}

=back

=cut

1;
