import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/presentation/admin/storage/storage_logic.dart';

void main() {
  test('bucketForFileType maps each deleted file type to its bucket', () {
    expect(bucketForFileType('avatar'), 'avatars');
    expect(bucketForFileType('document'), 'employee-documents');
    expect(bucketForFileType('pledge'), 'loan-pledges');
    expect(bucketForFileType('logo'), 'company-logos');
    expect(bucketForFileType('other'), 'employee-documents');
  });

  test('sumTrashBytes ignores rows without a size', () {
    expect(sumTrashBytes([
      {'file_size_bytes': 100},
      {'file_size_bytes': null},
      {'file_size_bytes': 2.5},
    ]), 102.5);
    expect(sumTrashBytes(const []), 0);
  });

  test('storageBucketTotals groups buckets; documents include the legacy bucket', () {
    final t = storageBucketTotals([
      {'bucket_name': 'avatars', 'total_size': 10},
      {'bucket_name': 'employee-documents', 'total_size': 20},
      {'bucket_name': 'documents', 'total_size': 5},
      {'bucket_name': 'loan-pledges', 'total_size': 7},
      {'bucket_name': 'company-logos', 'total_size': 3},
      {'bucket_name': 'ota-updates', 'total_size': null},
    ]);
    expect((t.avatars, t.documents, t.pledges, t.others), (10.0, 25.0, 7.0, 3.0));
  });

  test('storageBucketTotals tolerates null or non-list results', () {
    final t = storageBucketTotals(null);
    expect((t.avatars, t.documents, t.pledges, t.others), (0.0, 0.0, 0.0, 0.0));
    expect(storageBucketTotals({'x': 1}).others, 0.0);
  });
}
