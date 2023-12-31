#!/usr/bin/perl

use strict;

use Test::More tests => 20;
use Test::Identity;
use Test::Refcount;

use Future;

{
   my $f1 = Future->new;
   my $f2 = Future->new;

   my $future = Future->wait_all( $f1, $f2 );
   is_oneref( $future, '$future has refcount 1 initially' );

   # Two refs; one lexical here, one in $future
   is_refcount( $f1, 2, '$f1 has refcount 2 after adding to ->wait_all' );
   is_refcount( $f2, 2, '$f2 has refcount 2 after adding to ->wait_all' );

   my @on_ready_args;
   $future->on_ready( sub { @on_ready_args = @_ } );

   ok( !$future->is_ready, '$future not yet ready' );
   is( scalar @on_ready_args, 0, 'on_ready not yet invoked' );

   $f1->done( one => 1 );

   ok( !$future->is_ready, '$future still not yet ready after f1 ready' );
   is( scalar @on_ready_args, 0, 'on_ready not yet invoked' );

   $f2->done( two => 2 );

   is( scalar @on_ready_args, 1, 'on_ready passed 1 argument' );
   identical( $on_ready_args[0], $future, 'Future passed to on_ready' );
   undef @on_ready_args;

   ok( $future->is_ready, '$future now ready after f2 ready' );
   my @results = $future->get;
   identical( $results[0], $f1, 'Results[0] from $future->get is f1' );
   identical( $results[1], $f2, 'Results[1] from $future->get is f2' );
   undef @results;

   is_refcount( $future, 1, '$future has refcount 1 at end of test' );
   undef $future;

   is_refcount( $f1,   1, '$f1 has refcount 1 at end of test' );
   is_refcount( $f2,   1, '$f2 has refcount 1 at end of test' );
}

{
   my $f1 = Future->new;
   $f1->done;

   my $on_ready_called;
   $f1->on_ready( sub { $on_ready_called++ } );

   is( $on_ready_called, 1, 'on_ready called synchronously for already ready' );

   my $future = Future->wait_all( $f1 );

   ok( $future->is_ready, '$future of already-ready sub already ready' );
   my @results = $future->get;
   identical( $results[0], $f1, 'Results from $future->get of already ready' );
}

{
   my $f1 = Future->new;
   my $c1;
   $f1->on_cancel( sub { $c1++ } );

   my $f2 = Future->new;
   my $c2;
   $f2->on_cancel( sub { $c2++ } );

   my $future = Future->wait_all( $f1, $f2 );

   $f2->done;

   $future->cancel;

   is( $c1, 1,     '$future->cancel marks subs cancelled' );
   is( $c2, undef, '$future->cancel ignores ready subs' );
}
