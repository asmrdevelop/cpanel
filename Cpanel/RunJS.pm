package Cpanel::RunJS;

# cpanel - Cpanel/RunJS.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use experimental 'isa';

=encoding utf-8

=head1 NAME

Cpanel::RunJS

=head1 SYNOPSIS

    my $floog_js = Cpanel::RunJS->new('@cpanel/floog.mjs');

    my $value = $floog_js->call( doTheThing => $floog_specimen );

The above corresponds to JavaScript:

    import * as FLOOG from '@cpanel/floog.mjs';

    let value = FLOOG.doTheThing(floog_specimen);  // returned

=head1 DESCRIPTION

This class runs JavaScript modules meant for execution in
both Perl and JavaScript.

=head1 SUBCLASS INTERFACE

It’s useful to subclass this module for individual JavaScript modules.
Toward that end, you can define the following Perl methods in subclasses:

=over

=item * C<_AFTER_IMPORT($exports_name)> - Instance method that returns
JavaScript code that runs after importing the JavaScript module.
The JavaScript exports are available under $exports_name.

=item * C<_JS_GLOBALS()> - Class method that returns a list of globals
to set.

=back

NB: This class is useful on its own; it doesn’t I<need> to be subclassed.
But if your JavaScript module needs any kind of special setup—e.g.,
localization—then a subclass offers a nice way to achieve that.

=cut

#----------------------------------------------------------------------

use JavaScript::QuickJS ();

use Carp       ();
use Data::Rmap ();

use Cpanel::ConfigFiles  ();
use Cpanel::JSON         ();
use Cpanel::UTF8::Deep   ();
use Cpanel::UTF8::Strict ();

# for tests:
our $_MODULE_BASE_PATH = "$Cpanel::ConfigFiles::CPANEL_ROOT/share/from_npm/node_modules";

# Subclass methods:
use constant _AFTER_IMPORT => q<>;
use constant _JS_GLOBALS   => ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( $MODULE_PATH )

Creates an object that reads and parses the module with the given
$MODULE_PATH, which is relative to cPanel’s F</base/sharedjs> directory.

($MODULE_PATH will I<probably> always include the C<@cpanel/> prefix,
but that’s not a requirement here.)

=cut

sub new ( $class, $module_path ) {

    # NOTE: The ugliness below is to avoid memory leaks. It’s solely
    # an implementation matter, not something that need concern callers.
    # See JavaScript::QuickJS’s documentation for the rationale.

    my $js = JavaScript::QuickJS->new(

        # CloudLinux 6, for whatever reason, requires a much larger (~10x)
        # stack size than newer OSes for the same JS file.
        #
        max_stack_size => 0,
    );

    $js->set_module_base($_MODULE_BASE_PATH);

    my $returned;

    my $module_path_json = Cpanel::JSON::Dump($module_path);

    $js->set_globals(
        $class->_JS_GLOBALS(),
        __cpreturn => sub ($got) {
            $returned = $got;
            return;
        },
    );

    # Load/cache the module:
    $js->eval_module(qq<import * as _ from $module_path_json>);

    my $exports = $returned;

    # Needed to prevent a memory leak:
    undef $returned;

    return bless {
        _js               => $js,
        _returned_sr      => \$returned,
        _module_path_json => $module_path_json,
    }, $class;
}

=head2 $result = I<OBJ>->call( $FUNCNAME, @ARGUMENTS )

Runs $FUNCNAME with a list of @ARGUMENTS.
Returns a Perl scalar that represents the JavaScript function’s return.

$FUNCNAME can be either the name of an exported global function, or a
named object method like C<myWidget.frobnicate> (which will run C<myWidget>’s
C<frobnicate()> method).

=head3 Numbers vs. Strings vs. Booleans

This module uses L<Cpanel::JSON>’s logic for converting Perl scalars
to JSON/JavaScript.

=head3 Character Encoding

Since this module interoperates with cPanel’s Perl code, strings in
@ARGUMENTS should be I<byte> strings, and all returned JavaScript
strings are encoded as UTF-8; hence, everything should “just work”.

=head3 Returned Functions

If the called JavaScript function returns another function (either simply
or inside a data structure), this interface represents that returned function
as a code reference, whose Perl arguments are translated to JavaScript
as described above. The return is processed the same way as well.

=cut

sub call ( $self, $func_name, @args ) {

    my $args_json = Cpanel::JSON::Dump( \@args );

    my $args_chars = Cpanel::UTF8::Strict::decode($args_json);

    my $exp_name = '_EXPORTED';

    my $after_import = $self->_AFTER_IMPORT($exp_name);

    $self->{'_js'}->helpers()->std()->os()->eval_module(
        <<~EOS
        import * as $exp_name from $self->{'_module_path_json'};
        $after_import;

        const pieces = "$func_name".split('.');

        // Last piece is just the method name.
        pieces.pop();

        let lastObject = $exp_name;
        let lastObjectPath = [];
        for (const p of pieces) {
            lastObjectPath.push(p);

            if (typeof lastObject[p] === "object") {
                lastObject = lastObject[p];
                continue;
            }

            const pathName = $self->{'_module_path_json'};
            throw `Nonexistext export: \${lastObjectPath.join('.')} (\${pathName})`;
        }

        if (!$exp_name.$func_name || (typeof($exp_name.$func_name) !== "function")) {
            throw `Non-function export ($exp_name.$func_name) call()ed`;
        }

        __cpreturn( $exp_name.$func_name(...$args_chars) );
        EOS
    );

    my $got = $self->{'_returned_sr'}->$*;

    # NB: We undef the referent scalar, not the reference itself,
    # to prevent a memory leak.
    #
    undef $self->{'_returned_sr'}->$*;

    return _munge_return_for_cp($got);
}

sub _munge_return_for_cp ($got) {
    my $out = Cpanel::UTF8::Deep::encode($got);

    Data::Rmap::rmap_all(
        sub {
            if ( $_ isa 'JavaScript::QuickJS::Function' ) {
                my $jsfunc = $_;

                $_ = sub (@args) {
                    my $unicode_args_ar = Cpanel::UTF8::Deep::decode_clone( \@args );

                    return _munge_return_for_cp( $jsfunc->(@$unicode_args_ar) );
                };
            }
        },
        $out,
    );

    return $out;
}

1;
