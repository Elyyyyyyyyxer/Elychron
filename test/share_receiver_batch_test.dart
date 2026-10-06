import 'package:celechron/utils/share_receiver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cold-start shares remain separate batches', () {
    const items = [
      SharedItem(text: 'first', batch: 'one'),
      SharedItem(name: 'photo', batch: 'one'),
      SharedItem(text: 'second', batch: 'two'),
    ];

    final batches = ShareReceiver.batches(items);
    expect(batches, hasLength(2));
    expect(batches.first, items.take(2).toList());
    expect(batches.last.single.text, 'second');
  });

  test('one Android or desktop share keeps its items together', () {
    const items = [SharedItem(text: 'caption'), SharedItem(name: 'file')];
    expect(ShareReceiver.batches(items), [items]);
  });
}
