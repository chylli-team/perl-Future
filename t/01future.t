#!/usr/bin/perl

use strict;

use Test::More tests => 44;
use Test::Fatal;
use Test::Identity;
use Test::Refcount;

use Future;

{
   my $future = Future->new;

   ok( defined $future, '$future defined' );
   isa_ok( $future, "Future", '$future' );
   is_oneref( $future, '$future has refcount 1 initially' );

   ok( !$future->is_ready, '$future not yet ready' );

   my @on_ready_args;
   identical( $future->on_ready( sub { @on_ready_args = @_ } ), $future, '->on_ready returns $future' );

   my @on_done_args;
   identical( $future->on_done( sub { @on_done_args = @_ } ), $future, '->on_done returns $future' );
   identical( $future->on_fail( sub { die "on_fail called for done future" } ), $future, '->on_fail returns $future' );

   identical( $future->done( result => "here" ), $future, '->done returns $future' );

   is( scalar @on_ready_args, 1, 'on_ready passed 1 argument' );
   identical( $on_ready_args[0], $future, 'Future passed to on_ready' );
   undef @on_ready_args;

   is_deeply( \@on_done_args, [ result => "here" ], 'Results passed to on_done' );

   ok( $future->is_ready, '$future is now ready' );
   is_deeply( [ $future->get ], [ result => "here" ], 'Results from $future->get' );

   is_oneref( $future, '$future has refcount 1 at end of test' );
}

# done_cb
{
   my $future = Future->new;

   my @on_done_args;
   $future->on_done( sub { @on_done_args = @_ } );

   my $done_cb = $future->done_cb;
   is( ref $done_cb, "CODE", '->done_cb returns CODE reference' );

   $done_cb->( result => "via cb" );
   is_deeply( \@on_done_args, [ result => "via cb" ], 'Results via ->done_cb' );
}

# Callable
{
   my $future = Future->new;

   my @on_done_args;
   $future->on_done( sub { @on_done_args = @_ } );

   $future->( another => "result" );

   is_deeply( \@on_done_args, [ another => "result" ], '$future is directly callable' );
}

{
   my $future = Future->new;

   $future->done( already => "done" );

   my @on_done_args;
   $future->on_done( sub { @on_done_args = @_; } );

   is_deeply( \@on_done_args, [ already => "done" ], 'Results passed to on_done for already-done future' );
}

# done chaining
{
   my $future = Future->new;

   my $f1 = Future->new;
   my $f2 = Future->new;

   $future->on_done( $f1 );
   $future->on_ready( $f2 );

   my @on_done_args_1;
   $f1->on_done( sub { @on_done_args_1 = @_ } );
   my @on_done_args_2;
   $f2->on_done( sub { @on_done_args_2 = @_ } );

   $future->done( chained => "result" );

   is_deeply( \@on_done_args_1, [ chained => "result" ], 'Results chained via ->on_done( $f )' );
   is_deeply( \@on_done_args_2, [ chained => "result" ], 'Results chained via ->on_ready( $f )' );
}

{
   my $future = Future->new;

   $future->on_done( sub { die "on_done called for failed future" } );
   my $failure;
   $future->on_fail( sub { ( $failure ) = @_; } );

   my $file = __FILE__;
   my $line = __LINE__+1;
   identical( $future->fail( "Something broke" ), $future, '->fail returns $future' );

   ok( $future->is_ready, '$future->fail marks future ready' );

   is( scalar $future->failure, "Something broke at $file line $line\n", '$future->failure yields exception' );
   is( exception { $future->get }, "Something broke at $file line $line\n", '$future->get throws exception' );

   is( $failure, "Something broke at $file line $line\n", 'Exception passed to on_fail' );
}

# fail_cb
{
   my $future = Future->new;

   my $failure;
   $future->on_fail( sub { ( $failure ) = @_ } );

   my $fail_cb = $future->fail_cb;
   is( ref $fail_cb, "CODE", '->fail_cb returns CODE reference' );

   $fail_cb->( "Failure by cb\n" );
   is( $failure, "Failure by cb\n", 'Failure via ->fail_cb' );
}

{
   my $future = Future->new;

   $future->fail( "Already broken" );

   my $failure;
   $future->on_fail( sub { ( $failure ) = @_; } );

   like( $failure, qr/^Already broken at /, 'Exception passed to on_fail for already-failed future' );
}

{
   my $future = Future->new;

   my $file = __FILE__;
   my $line = __LINE__+1;
   $future->fail( "Something broke", further => "details" );

   ok( $future->is_ready, '$future->fail marks future ready' );

   is( scalar $future->failure, "Something broke at $file line $line\n", '$future->failure yields exception' );
   is_deeply( [ $future->failure ], [ "Something broke at $file line $line\n", "further", "details" ],
         '$future->failure yields details in list context' );
}

# fail chaining
{
   my $future = Future->new;

   my $f1 = Future->new;
   my $f2 = Future->new;

   $future->on_fail( $f1 );
   $future->on_ready( $f2 );

   my $failure_1;
   $f1->on_fail( sub { ( $failure_1 ) = @_ } );
   my $failure_2;
   $f2->on_fail( sub { ( $failure_2 ) = @_ } );

   $future->fail( "Chained failure\n" );

   is( $failure_1, "Chained failure\n", 'Failure chained via ->on_fail( $f )' );
   is( $failure_2, "Chained failure\n", 'Failure chained via ->on_ready( $f )' );
}

# cancel
{
   my $future = Future->new;

   my $cancelled;

   $future->on_cancel( sub { $cancelled .= "1" } );
   $future->on_cancel( sub { $cancelled .= "2" } );

   my $ready;
   $future->on_ready( sub { $ready++ if shift->is_cancelled } );

   $future->on_done( sub { die "on_done called for cancelled future" } );
   $future->on_fail( sub { die "on_fail called for cancelled future" } );

   $future->cancel;

   ok( $future->is_ready, '$future->cancel marks future ready' );

   ok( $future->is_cancelled, '$future->cancelled now true' );
   is( $cancelled, "21",      '$future cancel blocks called in reverse order' );

   is( $ready, 1, '$future on_ready still called by cancel' );

   like( exception { $future->get }, qr/cancelled/, '$future->get throws exception by cancel' );
}

# cancel_cb
{
   my $future = Future->new;

   my $cancelled;
   $future->on_cancel( sub { $cancelled++ } );

   my $cancel_cb = $future->cancel_cb;
   is( ref $cancel_cb, "CODE", '->cancel_cb returns CODE reference' );

   $cancel_cb->();
   is( $cancelled, 1, 'Cancellation via ->cancel_cb' );
}

# cancel chaining
{
   my $f1 = Future->new;
   my $f2 = Future->new;

   $f1->on_cancel( $f2 );
   my $cancelled;
   $f2->on_cancel( sub { $cancelled++ } );

   $f1->cancel;
   is( $cancelled, 1, 'Chained cancellation' );
}

# Transformations
{
   my $f1 = Future->new;

   my $future = $f1->transform(
      done => sub { result => @_ },
   );

   $f1->done( 1, 2, 3 );

   is_deeply( [ $future->get ], [ result => 1, 2, 3 ], '->transform result' );

   $f1 = Future->new;

   $future = $f1->transform(
      fail => sub { "failure\n" => @_ },
   );

   $f1->fail( "something failed\n" );

   is_deeply( [ $future->failure ], [ "failure\n" => "something failed\n" ], '->transform failure' );

   $f1 = Future->new;
   my $cancelled;
   $f1->on_cancel( sub { $cancelled++ } );

   $future = $f1->transform;

   $future->cancel;
   is( $cancelled, 1, '->transform cancel' );
}
