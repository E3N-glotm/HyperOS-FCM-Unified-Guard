# PowerKeeper ר������� ROM ʵ�����ߣ�

Ŀ�꣺һ�� Magisk ģ�顢������ LSPosed���ﵽ�� Millet Guard + E3N FCM Live ��ʵ����Ϊ�������ٺ�̨������

## ��ǰ��ʵ��

- �޻��͡��汾�� ROM ��ϣ����������Ӧ�� ClassLoader ����ʵ�����Ĳ����ͷ�����������ƥ�䡣
- �ɰ� GmsObserver �����ӡ����硢���������� boolean �����Լ� NetdExecutor.initGmsChain �Ĵ�����
- �°� GmsObserver.updateFrameworkGmsNetStatus(boolean) �����β��������������ǰ������ Greeze Binder �����޸�ʱ����״̬�ض���һ�¡�
- PowerKeeper ���� Doze �������� GMS������ԭ�����������ݲ����޸ĵ� List��
- ÿ��ܶ���ʧ�ܡ��������档�Ҳ���ĳ�� OEM ���������������������������ֹͣ���� FCM �ػ���
- Android Java �Ž� DEX ��������/�°桢��ͬǩ����ȱʧ�������쳣�����ɱ� List �Ŀ� ROM ģ����ԡ�

## �������ֵ�״̬

1. ͨ�� OEM APK DEX �ҵ���ѡ������ֻ˵��ǩ�����ڡ�
2. ��ԭ�� ART Hook ��װ���سɹ�����˵������ʱ��װ�ɹ����Բ�֤������ʵ�ʱ����á�
3. ��˫ģ����Ϊ��Ч��������۲���á�����״̬�������� FCM ��Ϣ�ʹＰ�ܺġ�

**Ŀǰȱ������Ŀ�� Android �豸��֤ͨ���� Zygisk/LSPlant ԭ��װ�ؿ⡣**
PowerKeeperRuntimeEntry.nativeHook ֻ���� JNI �ӿڣ����������з���ģ���е��á�
��Ŀ¼�� DEX ������� alpha.6 ����ʽ ZIP����ǰ Magisk ��̬ 10/10 ά�ֶ���������

## Zygisk-only ԭ����ѡ��Դ��ʵ�飬��ֱֹ�ӷ�����

native/Bridge.cpp �ṩֻ��� PowerKeeper ���̵� Zygisk װ����ڣ�������������ж�أ�
��Ӧ�ô���ǰһ���Զ�ȡ�Ž� DEX ���ϴ� OEM ̽�ⱨ�棻ֻ��Ŀ����̳�ʼ�� LSPlant/Dobby��
���� Application.attach �õ�������Ӧ�� ClassLoader ������������� Java ���ԡ�
û�����ӳ�פ�ػ��̣߳�Ҳ�����޸� system_server �� PowerKeeper.apk��

native/ArtSymbols.cpp �ṩԭ�� libart ELF ���Ž�������������豸��������Ҫ�ķ��ţ�
��ú�ѡ����ʧ�ܹرն���Ӱ�� Magisk ���ġ����Ǿɰ�/�°�� ROM �����һ����Ҫ��ȷ���ԡ�

���� Android NDK r27 �� native/Bridge.cpp �� native/ArtSymbols.cpp
ִ�� arm64 C++23 �﷨���ͨ��������δ��� LSPlant / Dobby ���������Ӽ��豸�� Hook ��֤��
GitHub �� powerkeeper-native-experiment �����������ֶ�������
���ɵĶ��������ڷǰ�װʽ���Բ����������ʽģ�� Release��

CI ԭ���������Ӹ��� NDK r30���Խ�� r28 Clang 19 �Ծɰ� LSPlant
���� C++23 ģ��ı������⡣�ø��Ĳ�Ӱ���û��豸�� Android �汾�������жϡ�

��ȡ��Դ�����ͱ��� arm64 ʵ���Զ����ƣ���Ҫ Linux��NDK �� CMake/Ninja����

    ./powerkeeper-runtime/fetch-deps.sh
    export ANDROID_NDK_HOME=/path/to/ndk
    ./powerkeeper-runtime/build-native.sh

������LSPlant��LGPL-3.0����Dobby��Apache-2.0����Zygisk API ͷ�ļ���ISC����
Դ�뼰����ʱ�������汾д�� dependency-versions.txt����ʹ native �����ɹ���
Ҳ��������ͨ����ʵ ART/PowerKeeper/�ĵ����գ���˲��ܻ�����ʽ�档

## ART ��ʼ��˳��ȫ�޸���ʵ�飩

���� `backport_lsplant_init_safety.py`���������ľɰ� LSPlant ����ֲ
2026-10-05 ������˼·������ ART �߳��Կ�����ʱ��� JNI/����Ԥ������
Ȼ��ȡ�� GC �ٽ�������ͣȫ�� ART �̣߳���ִ���ڲ� Hook ��װ�׶Ρ�
����ͨ���̶�Դ��ê��ƥ�估 `--verify` �İ�ȫ��������飬��ֹ
���ָ���ʧ����Ȼ�����ɹ�����̬��֤������������豸������/�����ָ���֤��

Ϊ��� 2026 �� 9 �º� LSPlant ���������� named std module��
��ǰʵ�鹹�������� 2026-09-02 ���ض�Դ���ύ�����ڹ���ʱӦ��
���� ART ��ʼ��˳�򲹶�����ֲ������������ʵ���������������ƣ�
**�����ʵ�� ART Hook���������ͱ�����������ǰ������ʽ����**��

## ���������

�Ӳֿ��Ŀ¼ִ�У�

    python3 powerkeeper-runtime/test_runtime.py
    python3 powerkeeper-runtime/build.py --sdk "$ANDROID_HOME" --jdk "$JAVA_HOME"

�õ� powerkeeper-runtime/build/powerkeeper-runtime.dex������һ�׶� Zygisk װ�ع������߼�顣���� DEX ���������� Hook��

## ��ʽ�����ż�

- ԭ�� Zygisk ģ��ֻ��ѡ��ʵ�� PowerKeeper ���̣��������̼�ʱ�˳�����������ѯ/������
- ��̬����Ŀ��Ӧ�� ClassLoader ����װ Hook���Ҳ����ӿ�ֻ�������
- Magisk �� Zygisk ʱ�����Ŀɶ������У����޸��κ�ǩ�� PowerKeeper.apk �� GMS Token��
- ����ͨ�� Android 17 ʵ�� ART Hook���������ޱ���������״̬����һ�¡�����֪ͨ��ʵ�ʹＰ��ʱ���������߲��ԣ��ſ�����ʽ������
