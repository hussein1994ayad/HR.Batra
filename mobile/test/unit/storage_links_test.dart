import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/services/storage_links.dart';

void main() {
  const base = 'https://x.supabase.co/storage/v1/object';

  test('private buckets are recognised with their object path', () {
    final ref = StorageLinks.parse('$base/public/employee-documents/e1/1789_r8.jpg');
    expect(ref?.bucket, 'employee-documents');
    expect(ref?.path, 'e1/1789_r8.jpg');
    expect(StorageLinks.parse('$base/public/loan-pledges/pledges/u1/p.png')?.path, 'pledges/u1/p.png');
  });

  test('already-signed links are re-signed from their path', () {
    final ref = StorageLinks.parse('$base/sign/loan-pledges/a/b.jpg?token=abc');
    expect(ref?.bucket, 'loan-pledges');
    expect(ref?.path, 'a/b.jpg');
  });

  test('public buckets and other urls are left alone', () {
    expect(StorageLinks.isPrivate('$base/public/avatars/u1.jpg'), isFalse);
    expect(StorageLinks.isPrivate('https://example.com/file.pdf'), isFalse);
  });

  test('encoded paths are decoded', () {
    expect(StorageLinks.parse('$base/public/employee-documents/leaves/u1/%D9%85.pdf')?.path, 'leaves/u1/م.pdf');
  });
}
